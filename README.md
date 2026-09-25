<p align="center">
  <img src="logo.svg" width="80" alt="Local-Echo logo">
</p>

<h1 align="center">Local-Echo</h1>

<p align="center">
  Local, private voice dictation for macOS. Hold a key, speak, release — your words appear at the cursor.<br>
  Everything runs on-device. No audio or text ever leaves your machine.
</p>

<p align="center">Powered by whisper.cpp and MLX on Apple Silicon.</p>

## Install

Local-Echo requires an Apple Silicon Mac with macOS 13 or later. To install or update it, run:

```bash
curl -fsSL https://raw.githubusercontent.com/NatanSlvdr/local-echo/main/scripts/install.sh | bash
```

The script downloads the latest [release](https://github.com/NatanSlvdr/local-echo/releases), checks its checksum, installs **Local-Echo.app** in `/Applications` (or `~/Applications` when `/Applications` is not writable), and starts it. Set `LOCAL_ECHO_VERSION=0.46.0` before `bash` to install a specific version.

You can also download the zip from the releases page and move the app to **Applications** yourself. The app is not notarized, so macOS blocks the first launch of a browser download: open it once, then choose **System Settings → Privacy & Security → Open Anyway**.

## Run from source

Local-Echo requires an Apple Silicon Mac, macOS 13 or later, the Xcode Command Line Tools, Git, CMake, and [`uv`](https://docs.astral.sh/uv/getting-started/installation/). The development script builds `whisper-cli` and `whisper-server` from [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and bundles the runtimes in the app. The selected speech and cleanup models download on first run.

From a checkout of this repository, run:

```bash
bash scripts/dev.sh
```

This builds a signed app at `~/Library/Application Support/Local-Echo/dev/Local-Echo.app` containing the model runtimes and launches it through macOS. The app keeps running after the command returns; choose **Quit** from the menu bar before rebuilding. Logs are written to `~/.config/local-echo/dev.log`. The finished app runs without separate Whisper or MLX installations. The Swift build script calls `swiftc` directly, so it also works with Command Line Tools installations where Swift Package Manager cannot load manifests.

The default Swift build uses debug symbols and skips optimization for faster iteration. The whisper.cpp binaries are reused until their pinned version or build recipe changes; run `bash scripts/build-whisper.sh --force` after editing its source. To check the optimized build through the same signed app workflow, quit the app and run `bash scripts/dev.sh release`.

When an Apple Development signing identity is available, the dev script uses it so macOS can keep the app's microphone permission across rebuilds. Otherwise the app is signed locally and macOS may ask for permission again after a rebuild.

A waveform icon appears in your menu bar when it's running.

The default hotkey is the **Globe key** (🌐, bottom-left). Hold it, speak, release.

On macOS 14 and later, Local-Echo can lower the system output volume while recording. Use **Audio → Baisser le son des autres apps** in the menu bar or the **Audio** settings page to turn this on or off. The original output volume is restored after recording. Microphone capture always uses the standard audio engine.

> **[Setup and permissions guide](docs/install-guide.md)** — permission walkthrough, non-English macOS instructions, and troubleshooting.

## Configuration

Edit `~/.config/local-echo/config.json`:

If you used the previous app name, Local-Echo copies your existing settings into this path on first launch and continues using models and saved recordings from `~/.config/open-wispr/`.

```json
{
  "hotkey": { "keyCode": 63, "modifiers": [] },
  "modelSize": "large-v3-turbo",
  "cleanupModel": "qwen35-08b-qat-q4",
  "cleanupOptions": {
    "formattingLevel": "light",
    "correctRecognitionErrors": true,
    "removeFillers": false
  },
  "whisperPrompt": "Use punctuation and capitalization.",
  "maxRecordings": 0,
  "toggleMode": false,
  "duckOtherAudioDuringRecording": false
}
```

After editing the file, choose **Réglages… → Avancé → Recharger la configuration** from the menu bar app.

To bind multiple hotkeys, use the `hotkeys` array instead:

```json
{
  "hotkeys": [
    { "keyCode": 63, "modifiers": [] },
    { "keyCode": 96, "modifiers": [] }
  ]
}
```

Both `hotkey` (single) and `hotkeys` (array) are supported. If both are present, `hotkeys` takes precedence.

| Option | Default | Values |
|---|---|---|
| **hotkey** | `63` | Globe (`63`), Right Option (`61`), F5 (`96`), or any key code |
| **hotkeys** | — | Array of hotkey objects — bind multiple keys to trigger dictation |
| **modifiers** | `[]` | `"cmd"`, `"ctrl"`, `"shift"`, `"opt"`, `"fn"` — combine for chords |
| **modelSize** | `"large-v3-turbo"` | `large-v3-turbo`, `qwen3-asr-1.7b-8bit`, `parakeet-tdt-v3-mixed`, or `qwen3-asr-1.7b-4bit` |
| **cleanupModel** | `"qwen35-08b-qat-q4"` | This Qwen3.5 cleanup model, or `"off"` |
| **cleanupOptions** | Light formatting and obvious-error correction on; filler removal off | `formattingLevel`: `none`, `light`, `polished` (paragraphs), or `structured` (paragraphs and lists when clearly dictated). Also choose obvious recognition corrections and filler/repetition removal. Missing fields use the defaults. Older `formatText` and `addParagraphs` settings are migrated. |
| **whisperPrompt** | — | Optional prompt text passed to Whisper to guide style, vocabulary, or punctuation. Omit it or leave it blank to use Whisper's default behavior. |
| **maxRecordings** | `0` | Optionally store past recordings locally as `.wav` files for re-transcribing from the tray menu. `0` = nothing stored (default). Set 1-100 to keep that many recent recordings. |
| **toggleMode** | `false` | Press hotkey once to start recording, press again to stop. Default is hold-to-talk. |
| **duckOtherAudioDuringRecording** | `false` | On macOS 14+, lower other apps' audio only while recording. Can also be changed from the menu bar. |

### Models

Choose among Qwen3 ASR INT8, compact Parakeet, balanced Qwen3 ASR Q4/Q8, and Whisper Large v3 Turbo. Cleanup uses Qwen3.5 0.8B QAT Q4. See [MODELS.md](MODELS.md) for IDs, sizes, and runtime details.

If the Globe key opens the emoji picker: **System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing"**

## Menu bar

Click the waveform icon to open a native macOS menu. The header shows the current state with a colored status badge, what to press next, and a progress bar while a model downloads. When a permission is missing, a button opens the right pane of System Settings.

- **Dernière dictée** — **Copier la dernière dictée** (⌘C) shows a preview of your most recent transcription and copies it, which helps if you dictated without a text field focused. When recordings are kept, **Enregistrements récents** lists them with their age and length; click one to re-transcribe it and copy the result.
- **Réglages rapides** — switch the speech model (with download size and status), the microphone and audio lowering, text cleanup and its formatting level, and the shortcut mode without opening the settings window.

| State | Icon |
|---|---|
| Idle | Waveform outline |
| Recording | Bouncing waveform |
| Transcribing | Wave dots |
| Downloading model | Progress ring |
| Waiting for permission | Lock |

Choose **Réglages…** (⌘,) to open the settings window, laid out like System Settings. **Général** explains how to dictate in three steps, shows whether the Microphone and Accessibility permissions are granted (with a button to fix them), and summarizes the current choices with links to each page. **Transcription** lists the four models from lightest to heaviest with a one-line description each, and flags models that still need downloading. **Nettoyage du texte** has an on/off switch, the four formatting levels with a "what you say / what you get" example for the selected one, and switches for obvious-error correction and filler removal. **Audio** picks the microphone, lowers other audio during dictation, and sets how many recordings to keep for re-transcription. **Raccourci** records a new shortcut, explains the Globe-key emoji setting when Fn is used, and chooses between holding and pressing. **Avancé** opens, reveals, or reloads the configuration file and can restore default settings after confirmation.

## Compare

| | Local-Echo | VoiceInk | Wispr Flow | Superwhisper | Apple Dictation |
|---|---|---|---|---|---|
| **Price** | **Free** | $39.99 | $15/mo | $8.49/mo | Free |
| **Open source** | MIT | GPLv3 | No | No | No |
| **100% on-device** | Yes | Yes | No | Yes | Partial |
| **Push-to-talk** | Yes | Yes | Yes | Yes | No |
| **AI features** | Local cleanup | AI assistant | AI rewriting | AI formatting | No |
| **Account required** | No | No | Yes | Yes | Apple ID |

## Privacy

Local-Echo is completely local. Audio is recorded to a temp file, transcribed by the selected local model, and the temp file is deleted. Network requests are only made to install the local MLX runtime and download selected models. Optionally, you can configure Local-Echo to store a number of past recordings locally via the `maxRecordings` setting. Those recordings stay private and on your machine, and we default to not storing anything.

## Roadmap

Feature requests and ideas are welcome as [issues](https://github.com/NatanSlvdr/local-echo/issues).

## Build from source

```bash
git clone https://github.com/NatanSlvdr/local-echo.git
cd local-echo
bash scripts/build-whisper.sh
bash scripts/build-swift.sh release
APP_DIR="$HOME/Library/Application Support/Local-Echo/dev/Local-Echo.app"
bash scripts/bundle-app.sh .build/release/local-echo "$APP_DIR" dev
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
open -a "$APP_DIR" --args start
```

`bundle-app.sh` copies the whisper.cpp binaries, `uv`, and the MLX worker into the app. The selected speech and cleanup models download on first launch to `~/.config/local-echo/models/`.

## Publish a release

From a clean `main` that matches `origin/main`, with the [GitHub CLI](https://cli.github.com) logged in, run:

```bash
bash scripts/release.sh           # current version if it has no tag yet, otherwise the next patch
bash scripts/release.sh minor     # or patch, major, or an explicit version such as 0.47.0
```

The script sets the version in `Sources/LocalEchoLib/Version.swift`, builds the optimized app, and zips it into `.build/dist/`. It then commits the version change, pushes a `vX.Y.Z` tag, and creates a GitHub release with the zip, its SHA-256 checksum, and generated notes. It signs with a Developer ID or Apple Development identity when one is installed. Set `LOCAL_ECHO_CODESIGN_IDENTITY` to choose another identity. Add `--dry-run` to build the zip without committing, tagging, or publishing.

## Support

Local-Echo is free and always will be. If you find it useful, you can [leave a tip](https://buy.stripe.com/4gM5kC2AU0Ssd4l6Hqd7q00).

## License

MIT
