#!/usr/bin/env python3
"""Score six widely spoken European languages on FLEURS without saving results."""

import argparse
import csv
import json
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import unicodedata
import uuid
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


DATASET = "google/fleurs"
REVISION = "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
LANGUAGES = {
    "en_us": "Anglais",
    "fr_fr": "Français",
    "de_de": "Allemand",
    "ru_ru": "Russe",
    "it_it": "Italien",
    "es_419": "Espagnol",
}
DEFAULT_PYTHON = Path.home() / ".config/local-echo/runtime/venv/bin/python"
DEFAULT_MODELS = Path.home() / ".config/local-echo/models"
DEFAULT_WHISPER_SERVER = (Path.home() / "Library/Application Support/Local-Echo/dev/Local-Echo.app"
                          / "Contents/MacOS/whisper-server")
WORKER = Path(__file__).resolve().parents[1] / "Resources/ModelRuntime/worker.py"


def normalized_words(text):
    """Ignore case, punctuation, and symbols in the word error rate."""
    text = unicodedata.normalize("NFC", text).casefold()
    return "".join(" " if unicodedata.category(char)[0] in "PS" else char for char in text).split()


def edit_distance(reference, hypothesis):
    """Count word insertions, deletions, and substitutions."""
    previous = list(range(len(hypothesis) + 1))
    for row, expected in enumerate(reference, 1):
        current = [row]
        for column, observed in enumerate(hypothesis, 1):
            current.append(min(
                previous[column] + 1,
                current[column - 1] + 1,
                previous[column - 1] + (expected != observed),
            ))
        previous = current
    return previous[-1]


def source_url(language, path):
    return f"https://huggingface.co/datasets/{DATASET}/resolve/{REVISION}/data/{language}/{path}"


def download_language(root, language, count):
    """Stream the test archive until it yields the requested distinct sentences."""
    directory = root / language
    directory.mkdir()
    with urlopen(source_url(language, "test.tsv"), timeout=60) as response:
        rows = csv.reader(response.read().decode("utf-8").splitlines(), delimiter="\t")
        references = {row[1]: (row[0], row[2]) for row in rows if len(row) >= 3}
    samples = []
    sentence_ids = set()
    with urlopen(source_url(language, "audio/test.tar.gz"), timeout=120) as response:
        with tarfile.open(fileobj=response, mode="r|gz") as archive:
            for member in archive:
                filename = Path(member.name).name
                entry = references.get(filename)
                if not member.isfile() or entry is None or entry[0] in sentence_ids:
                    continue
                source = archive.extractfile(member)
                if source is None:
                    continue
                audio_path = directory / filename
                audio_path.write_bytes(source.read())
                samples.append((audio_path, entry[1]))
                sentence_ids.add(entry[0])
                if len(samples) == count:
                    break
    if len(samples) != count:
        raise RuntimeError(f"{language}: only {len(samples)} of {count} samples found")
    print(f"{LANGUAGES[language]} : {count} extraits téléchargés", flush=True)
    return samples


class MLXWorker:
    """Send requests to Local-Echo's speech or cleanup worker."""

    def __init__(self, python, backend, model_directory):
        self.process = subprocess.Popen(
            [str(python), str(WORKER), "serve", backend, str(model_directory)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        if self._read().get("ready") is not True:
            raise RuntimeError(f"{backend} did not start")

    def _read(self):
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(f"Model worker exited with status {self.process.poll()}")
        return json.loads(line)

    def request(self, values):
        self.process.stdin.write(json.dumps(values, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        answer = self._read()
        if "error" in answer:
            raise RuntimeError(answer["error"])
        return answer["text"].strip()

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=30)


class InvalidTranscriptError(RuntimeError):
    """The app would reject a non-UTF-8 Whisper response as well."""


class WhisperWorker:
    """Use the same persistent whisper-server arguments and request as the app."""

    def __init__(self, binary, model):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        self.process = subprocess.Popen([
            str(binary), "--model", str(model), "--host", "127.0.0.1", "--port", str(self.port),
            "--language", "auto", "--no-timestamps", "--max-context", "0",
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(150):
            if self.process.poll() is not None:
                raise RuntimeError(f"whisper-server exited with status {self.process.returncode}")
            try:
                with urlopen(f"http://127.0.0.1:{self.port}/health", timeout=1) as response:
                    if response.status == 200:
                        return
            except (URLError, TimeoutError):
                time.sleep(0.1)
        self.close()
        raise RuntimeError("whisper-server did not start")

    def request(self, values):
        boundary = f"LocalEcho{uuid.uuid4().hex}"
        body = bytearray()
        for name, value in (("response_format", "text"), ("language", "auto"),
                            ("no_timestamps", "true"), ("max_context", "0")):
            body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
        body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
                    'filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode())
        body.extend(Path(values["audio"]).read_bytes())
        body.extend(f"\r\n--{boundary}--\r\n".encode())
        request = Request(f"http://127.0.0.1:{self.port}/inference", data=body,
                          headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        with urlopen(request, timeout=300) as response:
            data = response.read()
        try:
            return data.decode("utf-8").strip()
        except UnicodeDecodeError as error:
            raise InvalidTranscriptError(f"Whisper returned invalid UTF-8 for {values['audio']}") from error

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=30)


def find_whisper_model(models):
    """Find the existing Turbo checkpoint without downloading another copy."""
    for directory in (models, Path.home() / ".config/open-wispr/models", Path.home() / ".cache/whisper"):
        candidate = directory / "ggml-large-v3-turbo.bin"
        if candidate.is_file():
            return candidate
    raise RuntimeError("Whisper Large v3 Turbo model is missing")


def transcribe(samples, worker):
    """Keep hypotheses only in memory and count failed Whisper responses."""
    hypotheses = {}
    failures = 0
    try:
        for language, entries in samples.items():
            outputs = []
            for audio_path, _ in entries:
                try:
                    outputs.append(worker.request({"audio": str(audio_path)}))
                except InvalidTranscriptError as error:
                    print(error, file=sys.stderr, flush=True)
                    outputs.append("")
                    failures += 1
            hypotheses[language] = outputs
            print(f"{LANGUAGES[language]} : {len(outputs)} transcriptions", flush=True)
    finally:
        worker.close()
    return hypotheses, failures


def score(samples, hypotheses):
    """Calculate corpus WER separately for each language."""
    result = {}
    for language, entries in samples.items():
        reference_words = [normalized_words(reference) for _, reference in entries]
        outputs = hypotheses[language]
        total = sum(len(words) for words in reference_words)
        errors = sum(edit_distance(words, normalized_words(output))
                     for words, output in zip(reference_words, outputs, strict=True))
        result[language] = errors / total if total else 0.0
    return result


def run(count, python, models, whisper_server, cleanup):
    """Run all models over one temporary FLEURS sample, then remove the audio."""
    if not python.is_file():
        raise RuntimeError(f"Python runtime missing: {python}")
    if not whisper_server.is_file():
        raise RuntimeError(f"Whisper server missing: {whisper_server}")
    for model_id in ("qwen3-asr-1.7b-4bit", "qwen3-asr-1.7b-8bit"):
        if not (models / model_id / ".local-echo-ready").is_file():
            raise RuntimeError(f"Speech model missing: {model_id}")
    if cleanup and not (models / "qwen35-08b-qat-q4/.local-echo-ready").is_file():
        raise RuntimeError("Cleanup model is missing")
    whisper_model = find_whisper_model(models)

    with tempfile.TemporaryDirectory(prefix="local-echo-fleurs-") as temporary:
        root = Path(temporary)
        samples = {language: download_language(root, language, count) for language in LANGUAGES}
        results = {}
        current, _ = transcribe(samples, MLXWorker(python, "qwenASR", models / "qwen3-asr-1.7b-4bit"))
        results["qwen4"] = score(samples, current)

        if cleanup:
            cleaner = MLXWorker(python, "cleanup", models / "qwen35-08b-qat-q4")
            try:
                cleaned = {}
                for language, outputs in current.items():
                    cleaned[language] = [cleaner.request({
                        "text": output,
                        "formatting_level": "structured",
                        "correct_recognition_errors": "true",
                        "remove_fillers": "true",
                    }) if output else "" for output in outputs]
                    print(f"{LANGUAGES[language]} : nettoyage terminé", flush=True)
            finally:
                cleaner.close()
            results["cleaned"] = score(samples, cleaned)

        qwen8, _ = transcribe(samples, MLXWorker(python, "qwenASR", models / "qwen3-asr-1.7b-8bit"))
        results["qwen8"] = score(samples, qwen8)
        whisper, failures = transcribe(samples, WhisperWorker(whisper_server, whisper_model))
        results["whisper"] = score(samples, whisper)

    print(f"\nFLEURS test · {count} phrases distinctes par langue · WER (plus bas = mieux)")
    columns = ["Langue", "Qwen 4-bit", "Qwen 8-bit", "Whisper Turbo"]
    if cleanup:
        columns.insert(2, "4-bit + nettoyage")
    print(" | ".join(columns))
    print(" | ".join("---" for _ in columns))
    for language, name in LANGUAGES.items():
        values = [name, f"{results['qwen4'][language]:.1%}"]
        if cleanup:
            values.append(f"{results['cleaned'][language]:.1%}")
        values.extend((f"{results['qwen8'][language]:.1%}", f"{results['whisper'][language]:.1%}"))
        print(" | ".join(values))
    if failures:
        print(f"Réponses Whisper UTF-8 invalides, comptées comme vides : {failures}")
    print("Audios et transcriptions temporaires supprimés.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=20, help="Distinct test sentences per language")
    parser.add_argument("--python", type=Path, default=DEFAULT_PYTHON)
    parser.add_argument("--models", type=Path, default=DEFAULT_MODELS)
    parser.add_argument("--whisper-server", type=Path, default=DEFAULT_WHISPER_SERVER)
    parser.add_argument("--no-cleanup", action="store_true", help="Skip the current cleanup stage")
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    try:
        run(args.count, args.python, args.models, args.whisper_server, not args.no_cleanup)
    except KeyboardInterrupt:
        print("Benchmark interrompu ; fichiers temporaires supprimés.", file=sys.stderr)
        return 130
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
