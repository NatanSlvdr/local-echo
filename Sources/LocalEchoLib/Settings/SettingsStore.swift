import AppKit
import Combine

// Shares live configuration and device state with the SwiftUI settings pages.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var isRecording = false
    @Published var selection: SettingsPage? = .general
    @Published var searchText = ""
    /// Text typed or dictated into the "Essayer" field; kept while the window stays open.
    @Published var trialText = ""
    @Published private(set) var isCapturingShortcut = false
    @Published private(set) var hasMicrophoneAccess = Permissions.hasMicrophoneAccess
    @Published private(set) var hasAccessibilityAccess = AXIsProcessTrusted()
    var presentError: ((Error) -> Void)?
    var confirmReset: (@escaping () -> Void) -> Void = { $0() }
    private let configStore: ConfigStore
    private var configObserver: AnyCancellable?
    private var captureMonitor: Any?
    private var modifierCandidate: HotkeyConfig?

    init(configStore: ConfigStore) {
        self.configStore = configStore
        config = configStore.config
        configObserver = configStore.$config.sink { [weak self] config in self?.config = config }
    }

    func refresh() {
        inputDevices = AudioDeviceManager.listInputDevices()
        hasMicrophoneAccess = Permissions.hasMicrophoneAccess
        hasAccessibilityAccess = AXIsProcessTrusted()
    }

    func setRecording(_ isRecording: Bool) {
        if self.isRecording != isRecording { self.isRecording = isRecording }
    }

    func show(_ page: SettingsPage) {
        cancelShortcutCapture()
        selection = page
    }

    func change(_ edit: (inout Config) -> Void) {
        do {
            try configStore.update(edit)
        } catch {
            presentError?(error)
        }
    }

    // MARK: - Microphone

    /// The picker tag of the configured microphone, or "default" for the system default.
    var selectedDevice: String {
        config.selectedInputDevice(in: inputDevices).map { String($0.id) } ?? "default"
    }

    var systemDefaultDeviceName: String? {
        inputDevices.first(where: \.isDefault)?.name
    }

    var selectedDeviceName: String {
        config.selectedInputDevice(in: inputDevices)?.name
            ?? systemDefaultDeviceName
            ?? "Par défaut du système"
    }

    func selectDevice(_ value: String) {
        let device = inputDevices.first { String($0.id) == value }
        change {
            $0.audioInputDeviceID = device?.id
            $0.audioInputDeviceUID = device?.uid
        }
    }

    // MARK: - Files and system settings

    func openConfiguration() {
        guard ensureConfigurationFile() else { return }
        NSWorkspace.shared.open(Config.configFile)
    }

    func revealConfiguration() {
        guard ensureConfigurationFile() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Config.configFile])
    }

    private func ensureConfigurationFile() -> Bool {
        guard !FileManager.default.fileExists(atPath: Config.configFile.path) else { return true }
        do {
            try config.save()
            return true
        } catch {
            presentError?(error)
            return false
        }
    }

    func revealRecordings() {
        RecordingStore.ensureDirectory()
        NSWorkspace.shared.open(RecordingStore.recordingsDir)
    }

    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func reloadConfiguration() {
        configStore.reload()
        refresh()
    }

    func resetDefaults() {
        confirmReset { [weak self] in
            self?.change { $0 = Config.defaultConfig }
        }
    }

    // MARK: - Shortcut capture

    // Records a key and all held Command, Shift, Option, and Control modifiers.
    func startShortcutCapture() {
        guard captureMonitor == nil else { cancelShortcutCapture(); return }
        isCapturingShortcut = true
        modifierCandidate = nil
        ShortcutCaptureGate.shared.setActive(true)
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }) else {
            cancelShortcutCapture()
            return
        }
        captureMonitor = monitor
    }

    func cancelShortcutCapture() {
        if let captureMonitor { NSEvent.removeMonitor(captureMonitor) }
        captureMonitor = nil
        modifierCandidate = nil
        isCapturingShortcut = false
        ShortcutCaptureGate.shared.setActive(false)
    }

    private func captureShortcut(_ event: NSEvent) {
        if event.type == .keyDown {
            guard !event.isARepeat else { return }
            if event.keyCode == 53 { cancelShortcutCapture(); return }
            saveShortcut(HotkeyConfig(keyCode: event.keyCode,
                                      modifiers: HotkeyConfig.modifierNames(in: event.modifierFlags)))
            return
        }

        guard event.type == .flagsChanged, let mask = HotkeyConfig.modifierFlag(forKeyCode: event.keyCode) else { return }
        if event.modifierFlags.contains(mask) {
            let ownName = HotkeyConfig.modifierNames(in: mask)
            modifierCandidate = HotkeyConfig(keyCode: event.keyCode,
                                             modifiers: HotkeyConfig.modifierNames(in: event.modifierFlags)
                                                 .filter { !ownName.contains($0) })
        } else if event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty,
                  let modifierCandidate {
            saveShortcut(modifierCandidate)
        }
    }

    private func saveShortcut(_ shortcut: HotkeyConfig) {
        cancelShortcutCapture()
        change { $0.hotkeys[0] = shortcut }
    }
}
