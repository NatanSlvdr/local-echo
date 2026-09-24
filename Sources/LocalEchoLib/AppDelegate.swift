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

        guard Transcriber.findWhisperBinary() != nil else {
            showError("whisper-cli not found. Rebuild Local-Echo.app with whisper-cli on PATH.")
            return
        }

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
        if !Transcriber.modelExists(modelSize: modelSize) {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress("Downloading \(modelSize) model...")
            do {
                try await Task.detached(priority: .userInitiated) { [weak self] in
                    try ModelDownloader.download(modelSize: modelSize) { percent in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadGeneration == generation else { return }
                            self.statusBar.updateDownloadProgress(
                                "Downloading \(modelSize) model... \(Int(percent))%",
                                percent: percent
                            )
                        }
                    }
                }.value
            } catch {
                guard generation == downloadGeneration else { return false }
                showError("Model download failed: \(error.localizedDescription)")
                return false
            }
            guard generation == downloadGeneration else { return false }
            statusBar.updateDownloadProgress(nil)
        }

        guard let modelPath = Transcriber.findModel(modelSize: modelSize),
              ModelDownloader.isValidGGMLFile(at: URL(fileURLWithPath: modelPath)) else {
            showError("Model file is corrupted. Re-download with: local-echo download-model \(modelSize)")
            return false
        }
        return true
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
        config = newConfig
        dictation.updateConfig(newConfig)
        installHotkeys()
        statusBar.buildMenu()
        print("Config updated: model=\(config.modelSize) hotkey=\(config.hotkeySummary())")

        if modelChanged {
            downloadGeneration += 1
            statusBar.updateDownloadProgress(nil)
            Task { [weak self] in
                guard let self, self.config.modelSize == newConfig.modelSize else { return }
                let ready = await self.ensureModel(newConfig.modelSize)
                if ready, case .downloading = self.statusBar.state {
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
