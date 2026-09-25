import AppKit

/// Wires application services and keeps UI configuration on the main actor.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configStore: ConfigStore!
    private var statusBar: StatusBarController!
    private var recorder: AudioRecorder!
    private var dictation: DictationController!
    private var hotkeyManagers: [HotkeyManager] = []
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private let permissionMonitor = PermissionMonitor()
    private var setupTask: Task<Void, Never>?
    private var downloadGeneration = 0

    private var config: Config { configStore.config }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        configStore = ConfigStore()
        statusBar = StatusBarController(configStore: configStore)
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
        migrateAudioDeviceUIDIfNeeded()
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        dictation = DictationController(recorder: recorder, statusBar: statusBar, configStore: configStore)
        statusBar.reprocessHandler = { [weak self] url in self?.dictation.reprocess(audioURL: url) }
        configStore.observe { [weak self] old, new in self?.configDidChange(from: old, to: new) }
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

        // A model chosen from the menu while setup waited replaces the one it started with.
        var speechModel = config.modelSize
        while true {
            guard await ensureModel(speechModel) else { return }
            guard config.modelSize != speechModel else { break }
            speechModel = config.modelSize
        }
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
        try? configStore.update { $0.audioInputDeviceUID = uid }
    }

    private func ensureModel(_ modelID: String) async -> Bool {
        downloadGeneration += 1
        let generation = downloadGeneration
        guard let model = ModelCatalog.model(modelID) else { return false }
        if !model.isInstalled {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress(model: modelID)
            do {
                try await Task.detached(priority: .userInitiated) { [weak self] in
                    try ModelDownloader.download(model) { percent in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadGeneration == generation else { return }
                            self.statusBar.updateDownloadProgress(model: modelID, percent: percent)
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

        if model.backend == .whisper && BundledBinaries.whisperServer == nil {
            showError("whisper-server not found. Rebuild Local-Echo.app.")
            return false
        }
        if model.backend == .whisper, model.whisperFileURL.map(ModelDownloader.isValidGGMLFile(at:)) != true {
            showError("Model file is corrupted. Re-download with: local-echo download-model \(modelID)")
            return false
        }
        return model.isInstalled
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

    private func configDidChange(from old: Config, to new: Config) {
        statusBar.buildMenu()
        guard dictation?.isReady == true else { return }
        dictation.configDidChange()
        if new.hotkeys != old.hotkeys { installHotkeys() }
        print("Config updated: model=\(new.modelSize) hotkey=\(new.hotkeySummary())")

        let modelChanged = new.modelSize != old.modelSize
        let cleanupChanged = new.cleanupModel != old.cleanupModel
        guard modelChanged || cleanupChanged else { return }
        downloadGeneration += 1
        statusBar.updateDownloadProgress(model: nil)
        Task { [weak self] in
            guard let self, self.config.modelSize == new.modelSize else { return }
            let speechReady = modelChanged ? await self.ensureModel(new.modelSize) : true
            var cleanupReady = true
            if cleanupChanged, let model = new.cleanupModel {
                cleanupReady = await self.ensureModel(model)
            }
            if speechReady && !cleanupReady {
                print("Cleanup model unavailable; dictation will use raw transcription until it is downloaded.")
                self.statusBar.state = .idle
                self.statusBar.buildMenu()
            } else if speechReady, case .downloading = self.statusBar.state {
                self.statusBar.state = .idle
                self.statusBar.buildMenu()
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
