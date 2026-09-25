# Models

Local-Echo offers four speech models. Choose one in **Options → Transcription** or with `local-echo set-model <id>`. The selected model downloads on first use. Each loaded model stays in memory for 15 minutes after its last use, then unloads automatically.

The settings window groups them by approximate download size: **lightweight** (under 1 GB), **medium** (1–1.5 GB), and **heavy** (over 1.5 GB). Each selectable row shows its name, size, and whether it is already downloaded.

| Choice | ID | Download | Reference speed | Notes |
|---|---|---:|---:|---|
| Quality | `qwen3-asr-1.7b-8bit` | ~2.5 GB | 30.5× real time | [Qwen3 ASR 1.7B INT8](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit) via MLX Audio |
| Compact | `parakeet-tdt-v3-mixed` | ~400 MB | 69× real time | [Parakeet TDT v3 mixed Q4/Q8](https://huggingface.co/MarkChen1214/parakeet-tdt-0.6b-v3-MLX-Mixed-4bit8bit), 25 European languages |
| Balanced | `qwen3-asr-1.7b-4bit` | ~1.2 GB | Faster than INT8 on the publisher's test | [Qwen3 ASR 1.7B Q4 decoder / Q8 encoder](https://huggingface.co/moona3k/mlx-qwen3-asr-1.7b-4bit) |
| Existing default | `large-v3-turbo` | ~1.6 GB | Depends on hardware | Whisper Large v3 Turbo via whisper.cpp |

Speed figures are model publisher benchmarks, not guarantees for this app or your Mac. The Parakeet figure excludes model loading. The Qwen models and Parakeet run on Apple Silicon through an isolated Python MLX environment. The app installs that environment on first use using bundled `uv`. Turbo uses a persistent local `whisper-server`. Audio and transcript processing stay on your Mac.

The cleanup stage runs after transcription and spoken punctuation processing. Its only model is [`qwen35-08b-qat-q4`](https://huggingface.co/YoozLabs/Qwen3.5-0.8B-qat-lean-4bit-mlx), a ~500 MB Qwen3.5 0.8B QAT Q4 model. Cleanup is enabled by default and can be switched off in **Options → Nettoyage du texte** or with `local-echo set-cleanup off`. By default it corrects punctuation, capitalization, spacing, and obvious recognition errors while aiming to preserve meaning. Generated edits can still be wrong, so check important dictation.

Cleanup defaults to light formatting and obvious-error correction, with filler removal off. The formatting level can be set to none, light punctuation and capitalization, polished paragraphs, or structured paragraphs and lists when the speaker clearly enumerates items. The separate spoken-punctuation option in Transcription runs before cleanup.

The app stores MLX checkpoints under `~/.config/local-echo/models/` and its Python environment under `~/.config/local-echo/runtime/`. Existing `medium`, `large-v3`, and other removed selections move to `large-v3-turbo` when the configuration loads. Previously downloaded files are left on disk.
