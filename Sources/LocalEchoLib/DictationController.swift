import AppKit

/// Owns a dictation session and keeps its mutable state on the main actor.
@MainActor
final class DictationController {
    private let recorder: AudioRecorder
    private let statusBar: StatusBarController
    private let inserter = TextInserter()
    private var config: Config
    private var transcriber: Transcriber
    private var lifecycle = RecordingLifecycle()
    private var currentRecordingURL: URL?
    private(set) var isReady = false

    init(recorder: AudioRecorder, statusBar: StatusBarController, config: Config) {
        self.recorder = recorder
        self.statusBar = statusBar
        self.config = config
        self.transcriber = Self.makeTranscriber(for: config)
        configureRecorder(for: config)
    }

    func start() {
        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()
        recorder.prepare()
    }

    func updateConfig(_ config: Config) {
        self.config = config
        transcriber = Self.makeTranscriber(for: config)
        configureRecorder(for: config)
        recorder.prepare()
    }

    private func configureRecorder(for config: Config) {
        recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: config.audioInputDeviceUID,
            legacyID: config.audioInputDeviceID
        )
        recorder.duckOtherAudio = config.duckOtherAudioEnabled
    }

    private static func makeTranscriber(for config: Config) -> Transcriber {
        Transcriber(
            modelSize: config.modelSize,
            whisperPrompt: config.whisperPrompt
        )
    }

    func keyDown() {
        guard isReady else { return }
        if !lifecycle.isRecording {
            guard case .idle = statusBar.state else { return }
            guard Transcriber.modelExists(modelSize: config.modelSize) else { return }
        }
        switch lifecycle.keyDown(toggleMode: config.toggleMode?.value ?? false) {
        case .startRecording: startRecording()
        case .stopRecording: stopRecording()
        case .none, .cancelRecording, .prepareRecorder: break
        }
    }

    func keyUp() {
        guard isReady else { return }
        if lifecycle.keyUp(toggleMode: config.toggleMode?.value ?? false) == .stopRecording {
            stopRecording()
        }
    }

    private func startRecording() {
        statusBar.state = .recording
        do {
            recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
                uid: config.audioInputDeviceUID,
                legacyID: config.audioInputDeviceID
            )
            let outputURL = Config.effectiveMaxRecordings(config.maxRecordings) == 0
                ? RecordingStore.tempRecordingURL()
                : RecordingStore.newRecordingURL()
            try recorder.startRecording(to: outputURL)
            currentRecordingURL = outputURL
            statusBar.buildMenu()
        } catch {
            print("Error: \(error.localizedDescription)")
            lifecycle.recordingStartFailed()
            currentRecordingURL = nil
            statusBar.state = .idle
            statusBar.buildMenu()
        }
    }

    private func stopRecording() {
        guard let audioURL = recorder.stopRecording() else {
            RecordingCancellation.discardTrackedPartialRecording(&currentRecordingURL)
            statusBar.state = .idle
            statusBar.buildMenu()
            return
        }

        currentRecordingURL = nil
        statusBar.state = .transcribing
        statusBar.buildMenu()

        // Capture settings before leaving the main actor. A config reload affects the next job.
        let transcriber = self.transcriber
        let cleanupEnabled = config.cleanupModel != nil
        let cleanupOptions = config.cleanupOptions
        let maxRecordings = Config.effectiveMaxRecordings(config.maxRecordings)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer {
                if maxRecordings == 0 { try? FileManager.default.removeItem(at: audioURL) }
            }
            let result = Result { () -> String in
                try TranscriptionPipeline.run(transcriber: transcriber, audioURL: audioURL,
                                              cleanupEnabled: cleanupEnabled, cleanupOptions: cleanupOptions)
            }
            if maxRecordings > 0 { RecordingStore.prune(maxCount: maxRecordings) }
            DispatchQueue.main.async { self.finishTranscription(result) }
        }
    }

    private func finishTranscription(_ result: Result<String, Error>) {
        switch result {
        case .success(let text):
            if !text.isEmpty {
                statusBar.lastTranscription = text
                inserter.insert(text: text)
            }
            if case .transcribing = statusBar.state { statusBar.state = .idle }
            statusBar.buildMenu()
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
            guard case .transcribing = statusBar.state else { return }
            statusBar.state = .error(error.localizedDescription)
            statusBar.buildMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                if case .error = self.statusBar.state {
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            }
        }
    }

    func systemWillSleep() {
        recorder.teardown()
        guard lifecycle.systemWillSleep() == .cancelRecording else { return }
        RecordingCancellation.discardTrackedPartialRecording(&currentRecordingURL)
        if case .recording = statusBar.state {
            statusBar.state = .idle
            statusBar.buildMenu()
        }
    }

    func systemDidWake() {
        guard lifecycle.systemDidWake(isReady: isReady) == .prepareRecorder else { return }
        configureRecorder(for: config)
        recorder.prepare()
    }

    func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }
        statusBar.state = .transcribing
        statusBar.buildMenu()

        let transcriber = self.transcriber
        let cleanupEnabled = config.cleanupModel != nil
        let cleanupOptions = config.cleanupOptions
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { () -> String in
                try TranscriptionPipeline.run(transcriber: transcriber, audioURL: audioURL,
                                              cleanupEnabled: cleanupEnabled, cleanupOptions: cleanupOptions)
            }
            DispatchQueue.main.async { self.finishReprocessing(result) }
        }
    }

    private func finishReprocessing(_ result: Result<String, Error>) {
        switch result {
        case .success(let text) where !text.isEmpty:
            statusBar.lastTranscription = text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            guard case .transcribing = statusBar.state else { return }
            statusBar.state = .copiedToClipboard
            statusBar.buildMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                if case .copiedToClipboard = self.statusBar.state {
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            }
        case .success:
            if case .transcribing = statusBar.state {
                statusBar.state = .idle
                statusBar.buildMenu()
            }
        case .failure(let error):
            print("Reprocess error: \(error.localizedDescription)")
            if case .transcribing = statusBar.state {
                statusBar.state = .idle
                statusBar.buildMenu()
            }
        }
    }
}

/// Applies optional text stages after speech recognition for both dictation and reprocessing.
enum TranscriptionPipeline {
    static func run(transcriber: Transcriber, audioURL: URL,
                    cleanupEnabled: Bool, cleanupOptions: CleanupOptions) throws -> String {
        let text = try transcriber.transcribe(audioURL: audioURL)
        guard cleanupEnabled, cleanupOptions.hasEdits, !text.isEmpty else { return text }
        do {
            return try ModelRuntime.shared.clean(text, options: cleanupOptions)
        } catch {
            fputs("Cleanup unavailable: \(error.localizedDescription)\n", Foundation.stderr)
            return text
        }
    }
}
