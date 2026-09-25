import AppKit

/// Owns a dictation session and keeps its mutable state on the main actor.
@MainActor
final class DictationController {
    private let recorder: AudioRecorder
    private let statusBar: StatusBarController
    private let configStore: ConfigStore
    private let inserter = TextInserter()
    private var lifecycle = RecordingLifecycle()
    private var currentRecordingURL: URL?
    private(set) var isReady = false

    private var config: Config { configStore.config }

    init(recorder: AudioRecorder, statusBar: StatusBarController, configStore: ConfigStore) {
        self.recorder = recorder
        self.statusBar = statusBar
        self.configStore = configStore
    }

    func start() {
        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()
        configureRecorder()
        recorder.prepare()
    }

    /// Applies audio settings after a configuration change. Transcription settings are read when each job starts.
    func configDidChange() {
        configureRecorder()
        recorder.prepare()
    }

    private func configureRecorder() {
        recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: config.audioInputDeviceUID,
            legacyID: config.audioInputDeviceID
        )
        recorder.duckOtherAudio = config.duckOtherAudioEnabled
    }

    func keyDown() {
        guard isReady else { return }
        if !lifecycle.isRecording {
            guard case .idle = statusBar.state else { return }
            guard ModelCatalog.isInstalled(config.modelSize) else { return }
        }
        switch lifecycle.keyDown(toggleMode: config.usesToggleMode) {
        case .startRecording: startRecording()
        case .stopRecording: stopRecording()
        case .none, .cancelRecording, .prepareRecorder: break
        }
    }

    func keyUp() {
        guard isReady else { return }
        if lifecycle.keyUp(toggleMode: config.usesToggleMode) == .stopRecording {
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
            TranscriptionJob(config: config).warmUp()
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

        let maxRecordings = Config.effectiveMaxRecordings(config.maxRecordings)
        transcribe(audioURL, afterwards: {
            if maxRecordings == 0 {
                try? FileManager.default.removeItem(at: audioURL)
            } else {
                RecordingStore.prune(maxCount: maxRecordings)
            }
        }, completion: finishTranscription)
    }

    /// Runs a job off the main actor with the current settings, then reports back on the main actor.
    private func transcribe(_ audioURL: URL, afterwards: @escaping @Sendable () -> Void = {},
                            completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        let job = TranscriptionJob(config: config)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try job.run(audioURL: audioURL) }
            afterwards()
            DispatchQueue.main.async { completion(result) }
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
        configureRecorder()
        recorder.prepare()
    }

    func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }
        statusBar.state = .transcribing
        statusBar.buildMenu()
        transcribe(audioURL, completion: finishReprocessing)
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
