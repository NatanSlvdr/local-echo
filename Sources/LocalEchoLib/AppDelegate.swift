import AppKit

/// Wires application services and keeps UI configuration on the main actor.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder: AudioRecorder!
    private var dictation: DictationController!
    private var config: Config!
    private var hotkeyManagers: [HotkeyManager] = []
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private let permissionMonitor = PermissionMonitor()
    private var setupTask: Task<Void, Never>?
    private var downloadGeneration = 0

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        registerSleepWakeObservers()
        setupTask = Task { await setup() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        setupTask?.cancel()
        ModelRuntime.shared.stopAll()
        permissionMonitor.stop()
        recorder?.teardown()
        unregisterSleepWakeObservers()
        for manager in hotkeyManagers { manager.stop() }
    }

    private func setup() async {
        config = Config.load()
        migrateAudioDeviceUIDIfNeeded()
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        dictation = DictationController(recorder: recorder, statusBar: statusBar, config: config)
        statusBar.reprocessHandler = { [weak self] url in self?.dictation.reprocess(audioURL: url) }
        statusBar.onConfigChange = { [weak self] config in self?.applyConfigChange(config) }
        statusBar.buildMenu()

        if !(await Permissions.requestMicrophone()) {
            statusBar.state = .waitingForMicrophonePermission
            statusBar.buildMenu()
            Permissions.openMicrophoneSettings()
            await permissionMonitor.waitUntil { Permissions.hasMicrophoneAccess }
        }
        guard !Task.isCancelled else { return }

        if !AXIsProcessTrusted() {
            statusBar.state = .waitingForPermission
            statusBar.buildMenu()
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            await permissionMonitor.waitUntil { AXIsProcessTrusted() }
        }
        guard !Task.isCancelled else { return }

        let modelSize = config.modelSize
        guard await ensureModel(modelSize) else { return }
        if let cleanupModel = config.cleanupModel {
            if !(await ensureModel(cleanupModel)) {
                print("Cleanup model unavailable; dictation will use raw transcription until it is downloaded.")
            }
        }
        guard !Task.isCancelled else { return }

        startListening()
    }

    /// Configs from older versions use an AudioDeviceID that may change after reboot.
    private func migrateAudioDeviceUIDIfNeeded() {
        guard config.audioInputDeviceUID == nil,
              let legacyID = config.audioInputDeviceID,
              let uid = AudioDeviceManager.getDeviceUID(deviceID: legacyID) else { return }
        config.audioInputDeviceUID = uid
        try? config.save()
    }

    private func ensureModel(_ modelSize: String) async -> Bool {
        downloadGeneration += 1
        let generation = downloadGeneration
        if !ModelDownloader.modelExists(modelSize) {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress(model: modelSize)
            do {
                try await Task.detached(priority: .userInitiated) { [weak self] in
                    try ModelDownloader.download(modelSize: modelSize) { percent in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadGeneration == generation else { return }
                            self.statusBar.updateDownloadProgress(model: modelSize, percent: percent)
                        }
                    }
                }.value
            } catch {
                guard generation == downloadGeneration else { return false }
                showError("Model download failed: \(error.localizedDescription)")
                return false
            }
            guard generation == downloadGeneration else { return false }
            statusBar.updateDownloadProgress(model: nil)
        }

        guard let model = ModelCatalog.model(modelSize) else { return false }
        if model.backend == .whisper && Transcriber.findWhisperServerBinary() == nil {
            showError("whisper-server not found. Rebuild Local-Echo.app.")
            return false
        }
        if model.backend == .whisper,
           (Transcriber.findModel(modelSize: modelSize).map {
               ModelDownloader.isValidGGMLFile(at: URL(fileURLWithPath: $0))
           } != true) {
            showError("Model file is corrupted. Re-download with: local-echo download-model \(modelSize)")
            return false
        }
        return ModelDownloader.modelExists(modelSize)
    }

    private func showError(_ message: String) {
        print("Error: \(message)")
        statusBar.state = .error(message)
        statusBar.buildMenu()
    }

    private func startListening() {
        installHotkeys()
        dictation.start()
        print("Local-Echo v\(LocalEcho.version)")
        print("Hotkey: \(config.hotkeySummary())")
        print("Model: \(config.modelSize)")
        print("Ready.")
    }

    private func installHotkeys() {
        for manager in hotkeyManagers { manager.stop() }
        hotkeyManagers = config.hotkeys.map { hotkey in
            let manager = HotkeyManager(keyCode: hotkey.keyCode, modifiers: hotkey.modifierFlags)
            manager.start(
                onKeyDown: { [weak self] in
                    DispatchQueue.main.async { self?.dictation.keyDown() }
                },
                onKeyUp: { [weak self] in
                    DispatchQueue.main.async { self?.dictation.keyUp() }
                }
            )
            return manager
        }
    }

    public func reloadConfig() {
        applyConfigChange(Config.load())
    }

    func applyConfigChange(_ newConfig: Config) {
        guard dictation?.isReady == true else { return }
        let modelChanged = newConfig.modelSize != config.modelSize
        let cleanupChanged = newConfig.cleanupModel != config.cleanupModel
        config = newConfig
        dictation.updateConfig(newConfig)
        installHotkeys()
        statusBar.buildMenu()
        print("Config updated: model=\(config.modelSize) hotkey=\(config.hotkeySummary())")

        if modelChanged || cleanupChanged {
            downloadGeneration += 1
            statusBar.updateDownloadProgress(model: nil)
            Task { [weak self] in
                guard let self, self.config.modelSize == newConfig.modelSize else { return }
                let speechReady = modelChanged ? await self.ensureModel(newConfig.modelSize) : true
                var cleanupReady = true
                if cleanupChanged, let model = newConfig.cleanupModel {
                    cleanupReady = await self.ensureModel(model)
                }
                let ready = speechReady && cleanupReady
                if speechReady && !cleanupReady {
                    print("Cleanup model unavailable; dictation will use raw transcription until it is downloaded.")
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                } else if ready, case .downloading = self.statusBar.state {
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            }
        }
    }

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepWakeObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dictation?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dictation?.systemDidWake() }
            },
        ]
    }

    private func unregisterSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in sleepWakeObservers { center.removeObserver(observer) }
        sleepWakeObservers = []
    }
}
