<p align="center">
  <img src="logo.svg" width="80" alt="Local-Echo logo">
</p>

<h1 align="center">Local-Echo</h1>

<p align="center">
  Local, private voice dictation for macOS. Hold a key, speak, release — your words appear at the cursor.<br>
  Everything runs on-device. No audio or text ever leaves your machine.
</p>

<p align="center">Powered by whisper.cpp and MLX on Apple Silicon.</p>

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

On macOS 14 and later, Local-Echo can lower the system output volume while recording. Use **Lower Other Audio While Recording** in the menu bar to turn this on or off. The original output volume is restored after recording. Microphone capture always uses the standard audio engine.

> **[Setup and permissions guide](docs/install-guide.md)** — permission walkthrough, non-English macOS instructions, and troubleshooting.

## Configuration

Edit `~/.config/local-echo/config.json`:

If you used the previous app name, Local-Echo copies your existing settings into this path on first launch and continues using models and saved recordings from `~/.config/open-wispr/`.

```json
{
  "hotkey": { "keyCode": 63, "modifiers": [] },
  "modelSize": "large-v3-turbo",
  "cleanupModel": "qwen35-08b-qat-q4",
  "spokenPunctuation": false,
  "whisperPrompt": "Use punctuation and capitalization.",
  "maxRecordings": 0,
  "toggleMode": false,
  "duckOtherAudioDuringRecording": false
}
```

After editing the file, choose **Options... → Reload Configuration** from the menu bar app.

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
| **modifiers** | `[]` | `"cmd"`, `"ctrl"`, `"shift"`, `"opt"` — combine for chords |
| **modelSize** | `"large-v3-turbo"` | `large-v3-turbo`, `qwen3-asr-1.7b-8bit`, `parakeet-tdt-v3-mixed`, or `qwen3-asr-1.7b-4bit` |
| **cleanupModel** | `"qwen35-08b-qat-q4"` | This Qwen3.5 cleanup model, or `"off"` |
| **spokenPunctuation** | `false` | Say "comma", "period", etc. to insert punctuation instead of auto-punctuation |
| **whisperPrompt** | — | Optional prompt text passed to Whisper to guide style, vocabulary, or punctuation. Omit it or leave it blank to use Whisper's default behavior. |
| **maxRecordings** | `0` | Optionally store past recordings locally as `.wav` files for re-transcribing from the tray menu. `0` = nothing stored (default). Set 1-100 to keep that many recent recordings. |
| **toggleMode** | `false` | Press hotkey once to start recording, press again to stop. Default is hold-to-talk. |
| **duckOtherAudioDuringRecording** | `false` | On macOS 14+, lower other apps' audio only while recording. Can also be changed from the menu bar. |

### Models

Choose among Qwen3 ASR INT8, compact Parakeet, balanced Qwen3 ASR Q4/Q8, and Whisper Large v3 Turbo. Cleanup uses Qwen3.5 0.8B QAT Q4. See [MODELS.md](MODELS.md) for IDs, sizes, and runtime details.

If the Globe key opens the emoji picker: **System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing"**

## Menu bar

Click the waveform icon for status and options. **Recent Recordings** lists your last recordings; click one to re-transcribe and copy the result to the clipboard.

| State | Icon |
|---|---|
| Idle | Waveform outline |
| Recording | Bouncing waveform |
| Transcribing | Wave dots |
| Downloading model | Progress ring |
| Waiting for permission | Lock |

Click the menu bar icon to access **Copy Last Dictation** — recovers your most recent transcription if you dictated without a text field focused.

Choose **Options...** to open the settings window. It contains the speech model, cleanup, and microphone selectors, recording switches, and buttons to open or reload the configuration file.

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

## Support

Local-Echo is free and always will be. If you find it useful, you can [leave a tip](https://buy.stripe.com/4gM5kC2AU0Ssd4l6Hqd7q00).

## License

MIT
