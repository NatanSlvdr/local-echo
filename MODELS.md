# Models

Local-Echo offers three multilingual Whisper models. It detects the spoken language automatically.

| Model | Size | Speed | Accuracy | Notes |
|---|---|---|---|---|
| **`large-v3-turbo`** | **1.6 GB** | **Moderate** | **Great** | **Default; fast multilingual dictation** |
| `medium` | 1.5 GB | Slower | Great | Multilingual dictation |
| `large-v3` | 3 GB | Slowest | Best | Highest accuracy (M1 Pro+ recommended) |

Existing configurations using another model are moved to `large-v3-turbo` on launch. The language setting from older configurations is ignored and removed when the configuration is saved.

Models are downloaded on demand from [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp/tree/main) on HuggingFace and cached in `~/.config/local-echo/models/`.
