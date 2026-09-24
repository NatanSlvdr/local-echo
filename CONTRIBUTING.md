# Contributing

Local-Echo is a macOS Swift app. Install a Swift 6 Xcode Command Line Tools release and CMake, then run the app from a checkout:

```bash
bash scripts/dev.sh
```

The script builds `whisper-cli` when needed, builds and signs `~/Library/Application Support/Local-Echo/dev/Local-Echo.app`, then launches it through macOS. The app keeps running after the script exits; quit it from the menu bar before rebuilding. See the [setup guide](docs/install-guide.md) for permissions and troubleshooting.

Use `bash scripts/dev.sh release` to check an optimized build through the same app packaging and launch path. If you edit the pinned `whisper.cpp` checkout, run `bash scripts/build-whisper.sh --force` before the next dev build.

## Project structure

- `Sources/LocalEchoLib/` contains the app lifecycle, audio capture, hotkeys, transcription, and configuration.
- `DictationController` owns the recording and transcription flow; `AppDelegate` wires it to permissions, hotkeys, and the menu bar.
- `Sources/LocalEcho/` contains the CLI entry point and app bundle launch logic.
- `Resources/AppIcon.icns` is copied into the app bundle by `scripts/bundle-app.sh`.
- `Tests/LocalEchoTests/` contains Swift unit tests.
- `scripts/test-transcription.sh` runs an optional integration test with `whisper-cli` and a speech model.

## Tests

Run the Swift tests with:

```bash
swift test
```

To test actual transcription, build the app and run:

```bash
bash scripts/test-transcription.sh
```

That script generates test audio with macOS speech tools and downloads the small `tiny.en` model if needed. Add focused unit tests for new logic and integration coverage when changing the transcription pipeline.

For changes to audio, permissions, hotkeys, or text insertion, use the signed app for a short real use check: launch it, grant permissions if prompted, dictate into another app, confirm text appears at the cursor, then quit and relaunch it. Also check the affected input device or menu setting. For model download changes, check a first launch without that model. Use the release mode before sharing a build.

## Making changes

Create a branch, make the change, run relevant tests, and open a pull request. Test audio and permission changes on a Mac because they depend on macOS hardware and system settings.

Check the [open issues](https://github.com/NatanSlvdr/local-echo/issues) for bugs and feature requests.

Keep the app small, use local processing, and match the existing code style. By contributing, you agree that your contributions are licensed under the MIT License.
