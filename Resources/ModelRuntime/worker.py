"""Local JSON-lines worker. One process owns one MLX model until its host closes it."""
import contextlib
import json
import re
import sys
from pathlib import Path


def cleanup_option(request, key, default):
    """Read a boolean option from the worker's string-valued request."""
    value = request.get(key)
    if value is None:
        return default
    return value is True or value == 'true'


def cleanup_prompt(request):
    """Build only the editing instructions selected in the app settings."""
    instructions = [
        'You edit speech transcripts. Preserve the original language and meaning. '
        'Make only the changes requested below. Output only the edited transcript, with no explanation.'
    ]
    formatting = request.get('formatting_level', 'light')
    if formatting == 'none':
        instructions.append('Keep punctuation, capitalization, line breaks, and layout unchanged. '
                            'Adjust spacing only where another enabled edit removes or replaces a word.')
    elif formatting == 'polished':
        instructions.append('Correct punctuation, capitalization, and spacing. Make sentences easy to read '
                            'and add paragraph breaks at natural topic changes. Do not create lists or headings.')
    elif formatting == 'structured':
        instructions.append('Correct punctuation, capitalization, and spacing. Organize ideas into readable '
                            'paragraphs. Use a short list only when the speaker clearly enumerates separate '
                            'items; keep narrative speech as prose. Do not invent items, headings, or content.')
    else:
        instructions.append('Correct punctuation, capitalization, and spacing. Keep existing paragraph breaks '
                            'and do not create lists or headings.')

    if cleanup_option(request, 'correct_recognition_errors', True):
        instructions.append('Correct only obvious speech-recognition errors; preserve names and intended wording.')
    else:
        instructions.append('Do not correct suspected recognition errors or replace words.')

    if cleanup_option(request, 'remove_fillers', False):
        instructions.append('Remove filler words and accidental word repetitions, but keep intentional repetitions.')
    else:
        instructions.append('Keep filler words, hesitations, and repetitions.')

    return ' '.join(instructions)


def cleanup_chunks(text, limit=1000):
    """Split long dictation while preserving its original whitespace."""
    chunks = []
    current = ''
    for token in re.findall(r'\s+|\S+', text):
        if current and len(current) + len(token) > limit and current.strip():
            chunks.append(current)
            current = ''
        current += token
    if current:
        chunks.append(current)
    return chunks


def prepare(repository, directory):
    from huggingface_hub import snapshot_download

    path = Path(directory)
    path.mkdir(parents=True, exist_ok=True)
    snapshot_download(repo_id=repository, local_dir=path)
    if not any(path.glob('*.safetensors')):
        raise RuntimeError('The model download contains no weights')
    (path / '.local-echo-ready').write_text(repository)


def load(backend, directory):
    if backend == 'qwenASRSession':
        from mlx_qwen3_asr import Session
        session = Session(model=directory)
        return lambda request: session.transcribe(request['audio']).text
    if backend == 'qwenASR':
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

        def clean_chunk(text, system_prompt):
            leading = text[:len(text) - len(text.lstrip())]
            trailing = text[len(text.rstrip()):]
            core = text.strip()
            if not core:
                return text
            prompt = tokenizer.apply_chat_template([
                {'role': 'system', 'content': system_prompt},
                {'role': 'user', 'content': core},
            ], add_generation_prompt=True, enable_thinking=False)
            result = generate(model, tokenizer, prompt=prompt,
                              max_tokens=min(1200, max(128, len(core) + 64)),
                              sampler=sampler, verbose=False)
            if '</think>' in result:
                result = result.split('</think>', 1)[1]
            return leading + (result.strip() or core) + trailing

        def clean(request):
            system_prompt = cleanup_prompt(request)
            return ''.join(clean_chunk(chunk, system_prompt) for chunk in cleanup_chunks(request['text']))

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
