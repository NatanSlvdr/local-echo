# Setup and Permissions

## Prerequisites

Local-Echo runs on macOS 13 or later. Install the Xcode Command Line Tools with `xcode-select --install`, and install CMake. The development script builds and bundles `whisper-cli` from source.

## Build and run

From a checkout of this repository:

```bash
bash scripts/dev.sh
```

The script builds and signs `~/Library/Application Support/Local-Echo/dev/Local-Echo.app`, then starts it through macOS. The app keeps running after the command returns; choose **Quit** from the menu bar to stop it before rebuilding. Logs are written to `~/.config/local-echo/dev.log`. On first run, Local-Echo downloads its default speech and cleanup models to `~/.config/local-echo/models/`.

Existing settings from `~/.config/open-wispr/config.json` are copied to the new configuration path on first launch. Previously downloaded models and saved recordings remain available from the old data directory. Because the app bundle identifier changed, macOS may ask you to grant Microphone and Accessibility access again.

To inspect the configuration or change it, use the built CLI:

```bash
.build/debug/local-echo status
.build/debug/local-echo set-hotkey f5
.build/debug/local-echo set-model parakeet-tdt-v3-mixed
```

Restart the app after changing settings.

## Granting permissions

Local-Echo needs Microphone access to record speech and Accessibility access to detect the hotkey and insert text. macOS prompts for these permissions when the app starts. Grant both to **Local-Echo**.

If you missed the Accessibility prompt, open **System Settings → Privacy & Security → Accessibility** and enable Local-Echo. If it is not listed, add `~/Library/Application Support/Local-Echo/dev/Local-Echo.app`. For Microphone access, use **System Settings → Privacy & Security → Microphone**.

On non-English macOS installations, the Settings names are translated; the app name **Local-Echo** stays the same.

| Language | Accessibility settings path |
|---|---|
| Italian | Impostazioni di Sistema → Privacy e sicurezza → Accessibilità |
| French | Réglages du système → Confidentialité et sécurité → Accessibilité |
| German | Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen |
| Spanish | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad |
| Portuguese | Ajustes do Sistema → Privacidade e Segurança → Acessibilidade |

## Troubleshooting

### `whisper-server` is not found

Run `bash scripts/build-whisper.sh`, then rebuild the app with `bash scripts/dev.sh`. Check that `~/Library/Application Support/Local-Echo/dev/Local-Echo.app/Contents/MacOS/whisper-cli` exists.

### Local-Echo waits for Accessibility permission

Enable Local-Echo in **System Settings → Privacy & Security → Accessibility**. If it is missing, add `~/Library/Application Support/Local-Echo/dev/Local-Echo.app` and restart the app.

### Microphone access was denied

Enable Local-Echo in **System Settings → Privacy & Security → Microphone**, then restart the app.

If Local-Echo is absent from the Microphone list, launch the signed app with `bash scripts/dev.sh` and check `~/.config/local-echo/dev.log` for `Microphone: requesting...` followed by `Microphone: granted`. Launching the executable directly from Terminal can make macOS attribute the request to Terminal instead of Local-Echo.

### Globe key opens the emoji picker

Set **System Settings → Keyboard → “Press 🌐 key to” → “Do Nothing”**.

### Configuration resets to defaults

If `~/.config/local-echo/config.json` contains invalid JSON or unsupported values, Local-Echo warns and uses defaults for that run. Fix the file, then restart the app.

## Language support

Local-Echo detects spoken language automatically with the selected model. See [MODELS.md](../MODELS.md) for choices and language coverage.
