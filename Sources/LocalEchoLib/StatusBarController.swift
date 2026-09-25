import AppKit
import AVFoundation

class MenuItemTarget: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

@MainActor
class StatusBarController: NSObject, NSMenuDelegate {
    var statusItem: NSStatusItem
    var animationTimer: Timer?
    var animationFrame = 0
    var animationFrames: [NSImage] = []
    private var downloadingModel: String?
    var downloadPercent: Double = 0
    private var copiedFeedback = false
    private var menuItemTargets: [MenuItemTarget] = []
    private let menu = NSMenu()
    private let headerView = StatusMenuHeaderView()
    private var isMenuOpen = false
    private var settingsWindow: SettingsWindowController?
    private let configStore: ConfigStore

    var reprocessHandler: ((URL) -> Void)?
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

    init(configStore: ConfigStore) {
        self.configStore = configStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarController.drawLogo(active: false)
            button.image?.isTemplate = true
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        buildMenu()
    }

    // MARK: - Public updates

    /// Refreshes everything that shows the current state. The menu itself is rebuilt when it opens.
    func buildMenu() {
        let config = configStore.config
        settingsWindow?.setRecording(isRecording)
        let content = headerContent(config: config)
        headerView.update(content)
        statusItem.button?.toolTip = "Local-Echo · \(content.title)"
        if isMenuOpen { populateMenu(config: config) }
    }

    /// Pass the model being downloaded, or nil once the download ends.
    func updateDownloadProgress(model: String?, percent: Double = 0) {
        downloadingModel = model
        downloadPercent = percent
        if case .downloading = state {
            setIcon(StatusBarController.drawDownloadProgress(downloadPercent))
        }
        if model == nil {
            buildMenu()
        } else {
            headerView.update(headerContent(config: configStore.config))
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        populateMenu(config: configStore.config)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu { isMenuOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === self.menu { isMenuOpen = false }
    }

    // MARK: - Header

    private func headerContent(config: Config) -> StatusMenuHeaderView.Content {
        let hotkey = config.hotkeyDisplaySummary()
        let toggleMode = config.usesToggleMode
        switch state {
        case .idle:
            return .init(symbol: "waveform", tint: .controlAccentColor, title: "Prêt à dicter",
                         detail: toggleMode ? "Appuyez sur \(hotkey) pour commencer" : "Maintenez \(hotkey) et parlez")
        case .recording:
            return .init(symbol: "mic.fill", tint: .systemRed, title: "Enregistrement…",
                         detail: toggleMode ? "Appuyez de nouveau sur \(hotkey) pour terminer" : "Relâchez \(hotkey) pour terminer")
        case .transcribing:
            return .init(symbol: "text.bubble.fill", tint: .systemPurple, title: "Transcription…",
                         detail: ModelCatalog.speechModel(config.modelSize)?.name ?? config.modelSize)
        case .downloading:
            let name = downloadingModel.flatMap { ModelCatalog.model($0)?.name } ?? "le modèle"
            let percent = downloadPercent > 0 ? " · \(Int(downloadPercent)) %" : ""
            return .init(symbol: "arrow.down", tint: .systemBlue, title: "Téléchargement…",
                         detail: "\(name)\(percent)", progress: downloadPercent)
        case .waitingForMicrophonePermission:
            return .init(symbol: "mic.slash.fill", tint: .systemOrange, title: "Accès au micro requis",
                         detail: "Autorisez Local-Echo dans Réglages Système.")
        case .waitingForPermission:
            return .init(symbol: "hand.raised.fill", tint: .systemOrange, title: "Accès Accessibilité requis",
                         detail: "Local-Echo en a besoin pour écrire le texte dicté.")
        case .copiedToClipboard:
            return .init(symbol: "checkmark", tint: .systemGreen, title: "Copié dans le presse-papiers",
                         detail: "Collez le texte avec ⌘V.")
        case .error(let message):
            return .init(symbol: "exclamationmark.triangle.fill", tint: .systemRed, title: "Un problème est survenu",
                         detail: message)
        }
    }

    // MARK: - Menu

    private func populateMenu(config: Config) {
        menuItemTargets = []
        menu.removeAllItems()

        headerView.update(headerContent(config: config))
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        menu.addItem(headerItem)
        if let permissionItem = makePermissionItem() {
            menu.addItem(permissionItem)
        }

        menu.addItem(.separator())
        addLastDictationSection(config: config)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Réglages rapides"))
        menu.addItem(makeModelItem(config: config))
        menu.addItem(makeMicrophoneItem(config: config))
        menu.addItem(makeCleanupItem(config: config))
        menu.addItem(makeShortcutItem(config: config))

        menu.addItem(.separator())
        let settingsItem = actionItem("Réglages…", symbol: "gearshape", key: ",") { [weak self] in
            self?.openSettings(page: nil)
        }
        menu.addItem(settingsItem)
        menu.addItem(actionItem("À propos de Local-Echo", symbol: "info.circle") { [weak self] in
            self?.openSettings(page: .about)
        })
        let quitItem = NSMenuItem(title: "Quitter Local-Echo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        setMenuIcon("power", on: quitItem)
        menu.addItem(quitItem)
    }

    private func makePermissionItem() -> NSMenuItem? {
        let item: NSMenuItem
        switch state {
        case .waitingForMicrophonePermission:
            item = actionItem("Ouvrir les réglages du micro…", symbol: "mic") {
                Permissions.openMicrophoneSettings()
            }
        case .waitingForPermission:
            item = actionItem("Ouvrir les réglages d'accessibilité…", symbol: "accessibility") {
                Permissions.openAccessibilitySettings()
            }
        default:
            return nil
        }
        if #available(macOS 14.0, *) {
            item.badge = NSMenuItemBadge(string: "Requis")
        }
        return item
    }

    private func addLastDictationSection(config: Config) {
        menu.addItem(sectionHeader("Dernière dictée"))

        let copyItem = NSMenuItem(title: copiedFeedback ? "Copiée !" : "Copier la dernière dictée",
                                  action: #selector(copyLastTranscription), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = lastTranscription != nil && !copiedFeedback
        setMenuIcon(copiedFeedback ? "checkmark" : "doc.on.doc", on: copyItem)
        if let lastTranscription { setSubtitle(Self.preview(lastTranscription), on: copyItem) }
        menu.addItem(copyItem)

        guard Config.effectiveMaxRecordings(config.maxRecordings) > 0 else { return }
        let recordings = RecordingStore.listRecordings()
        let recordingsItem = NSMenuItem(title: "Enregistrements récents", action: nil, keyEquivalent: "")
        setMenuIcon("clock.arrow.circlepath", on: recordingsItem)
        if #available(macOS 14.0, *), !recordings.isEmpty {
            recordingsItem.badge = NSMenuItemBadge(count: recordings.count)
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if recordings.isEmpty {
            let emptyItem = NSMenuItem(title: "Aucun enregistrement", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            submenu.addItem(sectionHeader("Retranscrire et copier"))
            let canReprocess = isIdle
            for recording in recordings {
                let title = Self.relativeDateFormatter.localizedString(for: recording.date, relativeTo: Date())
                let item = actionItem(title.prefix(1).uppercased() + title.dropFirst()) { [weak self] in
                    self?.reprocessHandler?(recording.url)
                }
                var details = [Self.displayDateFormatter.string(from: recording.date)]
                if let duration = Self.duration(of: recording.url) { details.append(duration) }
                setSubtitle(details.joined(separator: " · "), on: item)
                item.isEnabled = canReprocess
                submenu.addItem(item)
            }
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Afficher dans le Finder", symbol: "folder") {
            RecordingStore.ensureDirectory()
            NSWorkspace.shared.open(RecordingStore.recordingsDir)
        })
        recordingsItem.submenu = submenu
        menu.addItem(recordingsItem)
    }

    private func makeModelItem(config: Config) -> NSMenuItem {
        let current = ModelCatalog.speechModel(config.modelSize)
        let item = NSMenuItem(title: "Modèle", action: nil, keyEquivalent: "")
        setMenuIcon("waveform", on: item)
        setSubtitle(current?.name ?? config.modelSize, on: item)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let canChange = !isBusy
        submenu.addItem(sectionHeader("Modèle de transcription"))
        // Lighter models first, matching the settings window.
        for model in ModelCatalog.speechByWeight {
            let modelItem = actionItem(model.name) { [weak self] in
                self?.changeConfig { $0.modelSize = model.id }
            }
            modelItem.state = model.id == config.modelSize ? .on : .off
            modelItem.isEnabled = canChange
            // Only a pending download is worth pointing out before switching.
            if !model.isInstalled {
                setSubtitle("À télécharger · \(model.approximateDownload)", on: modelItem)
            }
            submenu.addItem(modelItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem("Gérer les modèles…") { [weak self] in
            self?.openSettings(page: .transcription)
        })

        item.submenu = submenu
        return item
    }

    private func makeMicrophoneItem(config: Config) -> NSMenuItem {
        let devices = AudioDeviceManager.listInputDevices()
        let systemDefault = devices.first(where: \.isDefault)
        let selected = config.selectedInputDevice(in: devices)

        let item = NSMenuItem(title: "Audio", action: nil, keyEquivalent: "")
        setMenuIcon("mic", on: item)
        setSubtitle(selected?.name ?? systemDefault?.name ?? "Par défaut du système", on: item)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let canChange = !isRecording
        submenu.addItem(sectionHeader("Entrée audio"))
        let defaultItem = actionItem("Par défaut du système") { [weak self] in
            self?.changeConfig {
                $0.audioInputDeviceID = nil
                $0.audioInputDeviceUID = nil
            }
        }
        defaultItem.state = selected == nil ? .on : .off
        defaultItem.isEnabled = canChange
        if let systemDefault { setSubtitle(systemDefault.name, on: defaultItem) }
        submenu.addItem(defaultItem)

        for device in devices {
            let deviceItem = actionItem(device.name) { [weak self] in
                self?.changeConfig {
                    $0.audioInputDeviceID = device.id
                    $0.audioInputDeviceUID = device.uid
                }
            }
            deviceItem.state = selected?.id == device.id ? .on : .off
            deviceItem.isEnabled = canChange
            submenu.addItem(deviceItem)
        }

        // A toggle here keeps the top-level menu free of a checkmark column.
        submenu.addItem(sectionHeader("Pendant la dictée"))
        submenu.addItem(makeDuckingItem(config: config))

        item.submenu = submenu
        return item
    }

    private func makeCleanupItem(config: Config) -> NSMenuItem {
        let enabled = config.cleanupModel != nil
        let options = config.cleanupOptions
        let item = NSMenuItem(title: "Nettoyage du texte", action: nil, keyEquivalent: "")
        setMenuIcon("wand.and.stars", on: item)
        setSubtitle(config.cleanupSummary, on: item)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(sectionHeader("Nettoyage après transcription"))
        let toggleItem = actionItem("Activer le nettoyage") { [weak self] in
            self?.changeConfig { $0.cleanupModel = $0.cleanupModel == nil ? ModelCatalog.cleanup.id : nil }
        }
        toggleItem.state = enabled ? .on : .off
        submenu.addItem(toggleItem)

        submenu.addItem(sectionHeader("Niveau de mise en forme"))
        for level in CleanupFormattingLevel.allCases {
            let levelItem = actionItem(level.title) { [weak self] in
                self?.changeConfig { $0.cleanupOptions.formattingLevel = level }
            }
            levelItem.state = options.formattingLevel == level ? .on : .off
            levelItem.isEnabled = enabled
            levelItem.toolTip = level.explanation
            submenu.addItem(levelItem)
        }

        submenu.addItem(sectionHeader("Corrections"))
        let corrections: [(String, WritableKeyPath<CleanupOptions, Bool>)] = [
            ("Corriger les erreurs évidentes", \.correctRecognitionErrors),
            ("Supprimer hésitations et répétitions", \.removeFillers),
        ]
        for (title, keyPath) in corrections {
            let correctionItem = actionItem(title) { [weak self] in
                self?.changeConfig { $0.cleanupOptions[keyPath: keyPath].toggle() }
            }
            correctionItem.state = options[keyPath: keyPath] ? .on : .off
            correctionItem.isEnabled = enabled
            submenu.addItem(correctionItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeShortcutItem(config: Config) -> NSMenuItem {
        let toggleMode = config.usesToggleMode
        let item = NSMenuItem(title: "Raccourci", action: nil, keyEquivalent: "")
        setMenuIcon("keyboard", on: item)
        setSubtitle(config.shortcutSummary, on: item)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(sectionHeader("Mode du raccourci"))
        let modes: [(String, Bool)] = [
            ("Maintenir pour dicter", false),
            ("Appuyer pour démarrer / arrêter", true),
        ]
        for (title, value) in modes {
            let modeItem = actionItem(title) { [weak self] in
                self?.changeConfig { $0.usesToggleMode = value }
            }
            modeItem.state = toggleMode == value ? .on : .off
            modeItem.isEnabled = !isRecording
            submenu.addItem(modeItem)
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Modifier le raccourci…") { [weak self] in
            self?.openSettings(page: .controls)
        })

        item.submenu = submenu
        return item
    }

    private func makeDuckingItem(config: Config) -> NSMenuItem {
        let item = actionItem("Baisser le son des autres apps") { [weak self] in
            self?.changeConfig { $0.duckOtherAudioEnabled.toggle() }
        }
        item.state = config.duckOtherAudioEnabled ? .on : .off
        item.toolTip = "Réduit le volume des autres apps pendant l'enregistrement, puis le rétablit."
        if #available(macOS 14.0, *) {
            item.isEnabled = !isRecording
        } else {
            item.isEnabled = false
        }
        return item
    }

    // MARK: - Actions

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

    /// Saves a change through the shared store, which also updates the settings window.
    private func changeConfig(_ edit: (inout Config) -> Void) {
        do {
            try configStore.update(edit)
        } catch {
            print("Error: could not save configuration: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
        }
    }

    private func openSettings(page: SettingsPage?) {
        // Let menu tracking finish before activating the settings window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let settingsWindow = self.settingsWindow ?? SettingsWindowController(configStore: self.configStore)
            self.settingsWindow = settingsWindow
            settingsWindow.refresh(isRecording: self.isRecording)
            if let page { settingsWindow.show(page: page) }
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            settingsWindow.showWindow(nil)
            settingsWindow.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Helpers

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    private var isBusy: Bool {
        switch state {
        case .recording, .transcribing: true
        default: false
        }
    }

    private func actionItem(_ title: String, symbol: String? = nil, key: String = "",
                            handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuItemTarget(handler: handler)
        menuItemTargets.append(target)
        let item = NSMenuItem(title: title, action: #selector(MenuItemTarget.invoke), keyEquivalent: key)
        item.target = target
        if let symbol { setMenuIcon(symbol, on: item) }
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    /// Shows secondary text under the title; older systems show it as a tooltip.
    private func setSubtitle(_ subtitle: String, on item: NSMenuItem) {
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.toolTip = subtitle
        }
    }

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

    private static func preview(_ text: String) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard singleLine.count > 60 else { return "« \(singleLine) »" }
        return "« \(singleLine.prefix(60).trimmingCharacters(in: .whitespaces))… »"
    }

    private static func duration(of url: URL) -> String? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        let seconds = Int((Double(file.length) / file.fileFormat.sampleRate).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static let menuLocale = Locale(identifier: "fr_FR")

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = menuLocale
        f.unitsStyle = .full
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = menuLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
