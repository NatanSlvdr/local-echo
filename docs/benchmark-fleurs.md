# FLEURS benchmark

This command compares Local-Echo's installed Qwen 4-bit, Qwen 8-bit, and Whisper Large v3 Turbo models on real speech from the [Google FLEURS test split](https://huggingface.co/datasets/google/fleurs). It also scores the current structured cleanup settings on Qwen 4-bit output.

The six languages are English, French, German, Russian, Italian, and Spanish. This starts with the [ranking by total speakers in Europe](https://www.berlitz.com/blog/most-spoken-languages-in-europe), including first and second-language speakers, then adds Spanish as requested. FLEURS provides `en_us` for English and `es_419` for Spanish, so those samples do not test British or Spanish accents from Spain.

Run from the repository root after installing the local model runtime and the three speech models:

```bash
python3 scripts/benchmark-fleurs.py
```

The command streams 20 distinct test sentences per language by default. Use `--count 50` for a larger sample or `--no-cleanup` to omit the cleanup stage. It prints one WER table in the terminal. Lower WER is better. Case and punctuation are ignored, but words and accents are preserved.

The WAV files are held in a system temporary directory only while the command runs. The command deletes that directory before printing the final table, including when a model or download fails. It writes no manifests, transcripts, CSV files, or reports to disk. Models already installed by Local-Echo remain installed.

All models receive the same downloaded audio in a run. The command tests model recognition directly, not the microphone, audio capture, or text insertion. Twenty clips per language make a repeatable diagnostic sample, not a broad quality guarantee.
