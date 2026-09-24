import AppKit

class MenuItemTarget: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

@MainActor
class StatusBarController: NSObject {
    var statusItem: NSStatusItem
    var animationTimer: Timer?
    var animationFrame = 0
    var animationFrames: [NSImage] = []
    private var downloadProgress: String?
    var downloadPercent: Double = 0
    private var copiedFeedback = false
    private var menuItemTargets: [MenuItemTarget] = []
    private var stateMenuItem: NSMenuItem?
    private var optionsWindow: OptionsWindowController?

    var reprocessHandler: ((URL) -> Void)?
    var onConfigChange: ((Config) -> Void)?
    var lastTranscription: String?

    enum State {
        case idle
        case recording
        case transcribing
        case downloading
        case waitingForMicrophonePermission
        case waitingForPermission
        case copiedToClipboard
        case error(String)
    }

    var state: State = .idle {
        didSet { updateIcon() }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarController.drawLogo(active: false)
            button.image?.isTemplate = true
        }

        buildMenu()
    }

    @objc private func copyLastTranscription() {
        guard let text = lastTranscription else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedFeedback = true
        buildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copiedFeedback = false
            self?.buildMenu()
        }
    }

    func updateDownloadProgress(_ text: String?, percent: Double = 0) {
        downloadProgress = text
        downloadPercent = percent
        if case .downloading = state {
            setIcon(StatusBarController.drawDownloadProgress(downloadPercent))
        }
        if let text = text, let item = stateMenuItem {
            let config = Config.load()
            let hotkeyDesc = config.hotkeySummary()
            item.title = "\(text) (hotkey: \(hotkeyDesc))"
        } else {
            buildMenu()
        }
    }

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // Keep every menu icon at a consistent size and visible in light and dark mode.
    private func setMenuIcon(_ symbolName: String, on item: NSMenuItem) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        item.image = image?.withSymbolConfiguration(configuration) ?? image
        item.image?.isTemplate = true
        if #available(macOS 27.0, *) {
            item.preferredImageVisibility = .visible
        }
    }

    func buildMenu() {
        menuItemTargets = []

        let config = Config.load()
        let hotkeyDesc = config.hotkeySummary()
        if optionsWindow?.window?.isVisible == true {
            optionsWindow?.refresh(config: config, isRecording: isRecording)
        }

        let menu = NSMenu()

        let stateLabel: String
        if let progress = downloadProgress {
            stateLabel = progress
        } else {
            switch state {
            case .idle: stateLabel = "Ready"
            case .recording: stateLabel = "Recording..."
            case .transcribing: stateLabel = "Transcribing..."
            case .downloading: stateLabel = "Downloading model..."
            case .waitingForMicrophonePermission: stateLabel = "Waiting for Microphone permission..."
            case .waitingForPermission: stateLabel = "Waiting for Accessibility permission..."
            case .copiedToClipboard: stateLabel = "Copied to clipboard"
            case .error(let message): stateLabel = "Error: \(message)"
            }
        }
        if case .waitingForMicrophonePermission = state {
            let target = MenuItemTarget {
                Permissions.openMicrophoneSettings()
            }
            menuItemTargets.append(target)
            let stateItem = NSMenuItem(title: "Grant Microphone Permission...", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            stateItem.target = target
            menu.addItem(stateItem)
            stateMenuItem = stateItem
        } else if case .waitingForPermission = state {
            let target = MenuItemTarget {
                Permissions.openAccessibilitySettings()
            }
            menuItemTargets.append(target)
            let stateItem = NSMenuItem(title: "Grant Accessibility Permission...", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            stateItem.target = target
            menu.addItem(stateItem)
            stateMenuItem = stateItem
        } else {
            let stateItem = NSMenuItem(title: "\(stateLabel) (hotkey: \(hotkeyDesc))", action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
            stateMenuItem = stateItem
        }

        let stateSymbol: String
        switch state {
        case .idle: stateSymbol = "waveform"
        case .recording: stateSymbol = "mic.fill"
        case .transcribing: stateSymbol = "waveform"
        case .downloading: stateSymbol = "arrow.down.circle"
        case .waitingForMicrophonePermission, .waitingForPermission: stateSymbol = "lock"
        case .copiedToClipboard: stateSymbol = "checkmark.circle"
        case .error: stateSymbol = "exclamationmark.triangle"
        }
        if let stateMenuItem { setMenuIcon(stateSymbol, on: stateMenuItem) }

        menu.addItem(NSMenuItem.separator())

        let optionsItem = NSMenuItem(title: "Options...", action: #selector(openOptions(_:)), keyEquivalent: ",")
        optionsItem.target = self
        optionsItem.isEnabled = true
        setMenuIcon("gearshape", on: optionsItem)
        menu.addItem(optionsItem)

        let lastText = lastTranscription
        let copyTitle = copiedFeedback ? "Copied!" : "Copy Last Dictation"
        let copyItem = NSMenuItem(title: copyTitle, action: lastText != nil && !copiedFeedback ? #selector(copyLastTranscription) : nil, keyEquivalent: "c")
        copyItem.target = self
        if lastText == nil || copiedFeedback { copyItem.isEnabled = copiedFeedback }
        setMenuIcon(copiedFeedback ? "checkmark" : "doc.on.doc", on: copyItem)
        menu.addItem(copyItem)

        if Config.effectiveMaxRecordings(config.maxRecordings) > 0 {
            let recordings = RecordingStore.listRecordings()
            let reprocessItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            if recordings.isEmpty {
                let emptyItem = NSMenuItem(title: "No recordings", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                submenu.addItem(emptyItem)
            } else {
                for (index, recording) in recordings.enumerated() {
                    let dateStr = StatusBarController.displayDateFormatter.string(from: recording.date)
                    let label = "\(dateStr) (\(index + 1))"
                    let target = MenuItemTarget { [weak self] in
                        self?.reprocessHandler?(recording.url)
                    }
                    menuItemTargets.append(target)
                    let item = NSMenuItem(title: label, action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
                    item.target = target
                    submenu.addItem(item)
                }
            }

            reprocessItem.submenu = submenu
            setMenuIcon("clock.arrow.circlepath", on: reprocessItem)
            menu.addItem(reprocessItem)
        }

        menu.addItem(NSMenuItem.separator())

        let titleItem = NSMenuItem(title: "Local-Echo v\(LocalEcho.version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        setMenuIcon("info.circle", on: titleItem)
        menu.addItem(titleItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        setMenuIcon("power", on: quitItem)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openOptions(_ sender: NSMenuItem) {
        // Let menu tracking finish before activating the settings window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.optionsWindow == nil {
                self.optionsWindow = OptionsWindowController { [weak self] config in
                    self?.onConfigChange?(config)
                }
            }
            guard let optionsWindow = self.optionsWindow else { return }
            optionsWindow.refresh(config: Config.load(), isRecording: self.isRecording)
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            optionsWindow.showWindow(nil)
            optionsWindow.window?.makeKeyAndOrderFront(nil)
        }
    }

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

}
