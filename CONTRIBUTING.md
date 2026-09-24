# Contributing

OpenWispr is a macOS Swift app. Build `whisper-cli` from [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and add it to `PATH`, then run the app from a checkout:

```bash
bash scripts/dev.sh
```

The script builds and signs `OpenWispr.app` in the checkout and starts it in the foreground. See the [setup guide](docs/install-guide.md) for permissions and troubleshooting.

## Project structure

- `Sources/OpenWisprLib/` contains the app lifecycle, audio capture, hotkeys, transcription, and configuration.
- `Sources/OpenWispr/` contains the CLI entry point and app bundle launch logic.
- `Resources/AppIcon.icns` is copied into the app bundle by `scripts/bundle-app.sh`.
- `Tests/OpenWisprTests/` contains Swift unit tests.
- `scripts/test-transcription.sh` runs an optional integration test with `whisper-cli` and a speech model.

## Tests

Run the Swift tests with:

```bash
swift test
```

To test actual transcription, put `whisper-cli` on `PATH` and run:

```bash
bash scripts/test-transcription.sh
```

That script generates test audio with macOS speech tools and downloads the small `tiny.en` model if needed. Add focused unit tests for new logic and integration coverage when changing the transcription pipeline.

## Making changes

Create a branch, make the change, run relevant tests, and open a pull request. Test audio and permission changes on a Mac because they depend on macOS hardware and system settings.

Check the [open issues](https://github.com/human37/open-wispr/issues) for bugs and feature requests. The [roadmap](https://github.com/users/human37/projects/2) shows what's planned.

Keep the app small, use local processing, and match the existing code style. By contributing, you agree that your contributions are licensed under the MIT License.
