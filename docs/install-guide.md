# Setup and Permissions

## Prerequisites

OpenWispr runs on macOS 13 or later. Install the Xcode Command Line Tools with `xcode-select --install`, and install CMake. The development script builds and bundles `whisper-cli` from source.

## Build and run

From a checkout of this repository:

```bash
bash scripts/dev.sh
```

The script builds and signs `/tmp/OpenWispr.app`, then opens it through macOS Launch Services. Quit OpenWispr from its menu bar icon when finished. On first run, OpenWispr downloads its default speech model to `~/.config/open-wispr/models/`.

To inspect the configuration or change it, use the built CLI:

```bash
.build/release/open-wispr status
.build/release/open-wispr set-hotkey f5
.build/release/open-wispr set-model small.en
```

Restart the app after changing settings.

## Granting permissions

OpenWispr needs Microphone access to record speech and Accessibility access to detect the hotkey and insert text. macOS prompts for these permissions when the app starts. Grant both to **OpenWispr**.

If you missed the Accessibility prompt, open **System Settings → Privacy & Security → Accessibility** and enable OpenWispr. If it is not listed, add `/tmp/OpenWispr.app`. For Microphone access, use **System Settings → Privacy & Security → Microphone**.

On non-English macOS installations, the Settings names are translated; the app name **OpenWispr** stays the same.

| Language | Accessibility settings path |
|---|---|
| Italian | Impostazioni di Sistema → Privacy e sicurezza → Accessibilità |
| French | Réglages du système → Confidentialité et sécurité → Accessibilité |
| German | Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen |
| Spanish | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad |
| Portuguese | Ajustes do Sistema → Privacidade e Segurança → Acessibilidade |

## Troubleshooting

### `whisper-cli` is not found

Run `bash scripts/build-whisper.sh`, then rebuild the app with `bash scripts/dev.sh`. Check that `/tmp/OpenWispr.app/Contents/MacOS/whisper-cli` exists.

### OpenWispr waits for Accessibility permission

Enable OpenWispr in **System Settings → Privacy & Security → Accessibility**. If it is missing, add `/tmp/OpenWispr.app` and restart the app.

### Microphone access was denied

Enable OpenWispr in **System Settings → Privacy & Security → Microphone**, then restart the app.

### Globe key opens the emoji picker

Set **System Settings → Keyboard → “Press 🌐 key to” → “Do Nothing”**.

### Configuration resets to defaults

If `~/.config/open-wispr/config.json` contains invalid JSON or unsupported values, OpenWispr warns and uses defaults for that run. Fix the file, then restart the app.

## Language support

OpenWispr defaults to English. To use another language, set a multilingual model and language code in `~/.config/open-wispr/config.json`:

```json
{
  "language": "it",
  "modelSize": "base"
}
```

The model downloads automatically on the next run. See [MODELS.md](../MODELS.md) for model choices.
