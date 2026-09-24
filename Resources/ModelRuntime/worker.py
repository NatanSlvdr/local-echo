"""Local JSON-lines worker. One process owns one MLX model until its host closes it."""
import contextlib
import json
import sys
from pathlib import Path


def prepare(repository, directory):
    from huggingface_hub import snapshot_download

    path = Path(directory)
    path.mkdir(parents=True, exist_ok=True)
    snapshot_download(repo_id=repository, local_dir=path)
    if not any(path.glob('*.safetensors')):
        raise RuntimeError('The model download contains no weights')
    (path / '.local-echo-ready').write_text(repository)


def load(backend, directory):
    if backend == 'qwenASR':
        if '4bit' in directory:
            from mlx_qwen3_asr import Session
            session = Session(model=directory)
            return lambda request: session.transcribe(request['audio']).text
        from mlx_audio.stt import load as load_asr
        model = load_asr(directory)
        return lambda request: model.generate(request['audio']).text
    if backend == 'parakeet':
        sys.path.insert(0, directory)
        from parakeet_unified_mlx import load_parakeet_mlx
        model = load_parakeet_mlx(directory)
        return lambda request: model.generate(request['audio']).text
    if backend == 'cleanup':
        from mlx_lm import generate, load as load_lm
        from mlx_lm.sample_utils import make_sampler
        model, tokenizer = load_lm(directory)
        sampler = make_sampler(temp=0)

        def clean_chunk(text):
            prompt = tokenizer.apply_chat_template([
                {'role': 'system', 'content': (
                    'You edit speech transcripts. Correct punctuation, capitalization, '
                    'spacing, obvious transcription errors and spoken punctuation. '
                    'Preserve the language, meaning, names, and wording. '
                    'Output only the corrected transcript, with no explanation.')},
                {'role': 'user', 'content': text},
            ], add_generation_prompt=True, enable_thinking=False)
            result = generate(model, tokenizer, prompt=prompt,
                              max_tokens=min(1200, max(128, len(text) + 64)),
                              sampler=sampler, verbose=False)
            if '</think>' in result:
                result = result.split('</think>', 1)[1]
            return result.strip() or text

        def clean(request):
            words = request['text'].split()
            chunks = []
            current = []
            length = 0
            for word in words:
                if current and length + len(word) + 1 > 1000:
                    chunks.append(' '.join(current))
                    current = []
                    length = 0
                current.append(word)
                length += len(word) + 1
            if current:
                chunks.append(' '.join(current))
            return ' '.join(clean_chunk(chunk) for chunk in chunks)

        return clean
    raise ValueError(f'Unknown backend: {backend}')


def serve(backend, directory):
    with contextlib.redirect_stdout(sys.stderr):
        run = load(backend, directory)
    print(json.dumps({'ready': True}), flush=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                result = run(request)
            print(json.dumps({'text': result}), flush=True)
        except Exception as exc:
            print(json.dumps({'error': str(exc)}), flush=True)


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'prepare':
            prepare(sys.argv[2], sys.argv[3])
        elif sys.argv[1] == 'serve':
            serve(sys.argv[2], sys.argv[3])
        else:
            raise ValueError('Expected prepare or serve')
    except Exception as exc:
        print(f'Model worker: {exc}', file=sys.stderr)
        sys.exit(1)
