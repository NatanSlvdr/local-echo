import AppKit
import SwiftUI

// Keeps the menu bar app's settings in a regular, native macOS window.
final class OptionsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore

    init(onConfigChange: @escaping (Config) -> Void) {
        settings = SettingsStore(onConfigChange: onConfigChange)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Réglages"
        window.center()
        window.minSize = NSSize(width: 780, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        settings.presentError = { [weak window] error in
            guard let window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
        settings.confirmReset = { [weak window] confirmed in
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "Rétablir les réglages par défaut ?"
            alert.informativeText = "Le modèle, le raccourci, l'audio et les autres réglages seront réinitialisés. Les modèles téléchargés ne seront pas supprimés."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Rétablir")
            alert.addButton(withTitle: "Annuler")
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { confirmed() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func windowWillClose(_ notification: Notification) {
        settings.cancelShortcutCapture()
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        settings.cancelShortcutCapture()
    }

    func refresh(config: Config, isRecording: Bool) {
        settings.refresh(config: config, isRecording: isRecording)
    }

    func show(page: SettingsPage) {
        settings.cancelShortcutCapture()
        settings.searchText = ""
        settings.selection = page
    }
}

// Shares live configuration and device state with the SwiftUI settings pages.
@MainActor
private final class SettingsStore: ObservableObject {
    @Published private(set) var config = Config.load()
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var isRecording = false
    @Published var selection: SettingsPage? = .general
    @Published var searchText = ""
    @Published private(set) var isCapturingShortcut = false
    var presentError: ((Error) -> Void)?
    var confirmReset: (@escaping () -> Void) -> Void = { $0() }
    private let onConfigChange: (Config) -> Void
    private var captureMonitor: Any?
    private var modifierCandidate: HotkeyConfig?

    init(onConfigChange: @escaping (Config) -> Void) {
        self.onConfigChange = onConfigChange
    }

    func refresh(config: Config, isRecording: Bool) {
        self.config = config
        self.isRecording = isRecording
        inputDevices = AudioDeviceManager.listInputDevices()
    }

    func change(_ edit: (inout Config) -> Void) {
        var updated = Config.load()
        edit(&updated)
        do {
            try updated.save()
            config = updated
            onConfigChange(updated)
        } catch {
            presentError?(error)
        }
    }

    var selectedDevice: String {
        if let uid = config.audioInputDeviceUID,
           let device = inputDevices.first(where: { $0.uid == uid }) {
            return String(device.id)
        }
        if config.audioInputDeviceUID == nil,
           let id = config.audioInputDeviceID,
           inputDevices.contains(where: { $0.id == id }) {
            return String(id)
        }
        return "default"
    }

    func selectDevice(_ value: String) {
        let device = inputDevices.first { String($0.id) == value }
        change {
            $0.audioInputDeviceID = device?.id
            $0.audioInputDeviceUID = device?.uid
        }
    }

    func openConfiguration() {
        let file = Config.configFile
        if !FileManager.default.fileExists(atPath: file.path) {
            do { try Config.defaultConfig.save() }
            catch { presentError?(error); return }
        }
        NSWorkspace.shared.open(file)
    }

    func revealConfiguration() {
        let file = Config.configFile
        if !FileManager.default.fileExists(atPath: file.path) {
            do { try Config.defaultConfig.save() }
            catch { presentError?(error); return }
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    func reloadConfiguration() {
        (NSApplication.shared.delegate as? AppDelegate)?.reloadConfig()
        refresh(config: Config.load(), isRecording: isRecording)
    }

    func resetDefaults() {
        confirmReset { [weak self] in
            guard let self else { return }
            self.change { $0 = Config.defaultConfig }
        }
    }

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
            saveShortcut(HotkeyConfig(keyCode: event.keyCode, modifiers: Self.modifiers(in: event.modifierFlags)))
            return
        }

        guard event.type == .flagsChanged else { return }
        let mask = Self.flag(for: event.keyCode)
        guard !mask.isEmpty else { return }
        if event.modifierFlags.contains(mask) {
            let names = Self.modifiers(in: event.modifierFlags)
            modifierCandidate = HotkeyConfig(keyCode: event.keyCode,
                                             modifiers: names.filter { $0 != Self.name(for: mask) })
        } else if event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty,
                  let modifierCandidate {
            saveShortcut(modifierCandidate)
        }
    }

    private func saveShortcut(_ shortcut: HotkeyConfig) {
        cancelShortcutCapture()
        change { $0.hotkeys[0] = shortcut }
    }

    private static func modifiers(in flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.command) { names.append("cmd") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.option) { names.append("opt") }
        if flags.contains(.control) { names.append("ctrl") }
        if flags.contains(.function) { names.append("fn") }
        return names
    }

    private static func flag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        case 63: .function
        default: []
        }
    }

    private static func name(for flag: NSEvent.ModifierFlags) -> String {
        switch flag {
        case .command: "cmd"
        case .shift: "shift"
        case .option: "opt"
        case .control: "ctrl"
        case .function: "fn"
        default: ""
        }
    }
}

enum SettingsPage: String, Hashable, CaseIterable {
    case general, transcription, cleanup, audio, controls, advanced, about

    var title: String {
        switch self {
        case .general: "Général"
        case .transcription: "Transcription"
        case .cleanup: "Nettoyage du texte"
        case .audio: "Audio"
        case .controls: "Contrôles"
        case .advanced: "Avancé"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .transcription: "waveform"
        case .cleanup: "wand.and.stars"
        case .audio: "mic.fill"
        case .controls: "keyboard.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .transcription: .blue
        case .cleanup: .purple
        case .audio: .orange
        case .controls: .red
        case .advanced: .indigo
        case .about: .teal
        }
    }

    var searchTerms: String {
        switch self {
        case .general: "vue d'ensemble astuces conseils démarrage"
        case .transcription: "modèle reconnaissance vocale ponctuation taille téléchargement"
        case .cleanup: "nettoyage correction texte modèle"
        case .audio: "microphone entrée son volume"
        case .controls: "enregistrement raccourci clavier touches combinaison maintien démarrer arrêter"
        case .advanced: "configuration fichier ouvrir recharger réinitialiser défaut"
        case .about: "version licence compatibilité code source"
        }
    }
}

// Uses native lists, symbols, forms, pickers, and switches so the window follows macOS appearance.
private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Rechercher un réglage", text: Binding(
                        get: { settings.searchText },
                        set: { settings.searchText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    if !settings.searchText.isEmpty {
                        Button {
                            settings.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

                List(selection: Binding(
                    get: { settings.selection },
                    set: { page in
                        settings.cancelShortcutCapture()
                        settings.selection = page
                    }
                )) {
                    if [.general, .transcription, .cleanup].contains(where: matches) {
                        Section("ESSENTIELS") {
                            if matches(.general) { sidebarItem(.general) }
                            if matches(.transcription) { sidebarItem(.transcription) }
                            if matches(.cleanup) { sidebarItem(.cleanup) }
                        }
                    }
                    if [.audio, .controls].contains(where: matches) {
                        Section("PÉRIPHÉRIQUES ET SAISIE") {
                            if matches(.audio) { sidebarItem(.audio) }
                            if matches(.controls) { sidebarItem(.controls) }
                        }
                    }
                    if [.advanced, .about].contains(where: matches) {
                        Section("APPLICATION") {
                            if matches(.advanced) { sidebarItem(.advanced) }
                            if matches(.about) { sidebarItem(.about) }
                        }
                    }
                    if !SettingsPage.allCases.contains(where: matches) {
                        Text("Aucun réglage trouvé")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
            }
            .tint(.blue)
            .frame(width: 235)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text((settings.selection ?? .general).title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(height: 44)
                Divider()

                Group {
                    switch settings.selection ?? .general {
                    case .general: generalPage
                    case .transcription: transcriptionPage
                    case .cleanup: cleanupPage
                    case .audio: audioPage
                    case .controls: controlsPage
                    case .advanced: advancedPage
                    case .about: aboutPage
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sidebarItem(_ page: SettingsPage) -> some View {
        HStack(spacing: 9) {
            Image(systemName: page.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(page.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(page.title)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 2)
        .tag(page)
    }

    private func matches(_ page: SettingsPage) -> Bool {
        let query = settings.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || page.title.localizedStandardContains(query)
            || page.searchTerms.localizedStandardContains(query)
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(.primary)
            Text(title)
        }
    }

    private func settingLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .frame(width: 18)
            Text(title)
        }
    }

    private func infoRow(_ title: String, value: String, symbol: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            settingLabel(title, symbol: symbol)
        }
    }

    private func cleanupSetting(_ title: String, symbol: String, detail: String,
                                keyPath: WritableKeyPath<CleanupOptions, Bool>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(
                get: { settings.config.cleanupOptions[keyPath: keyPath] },
                set: { enabled in settings.change { $0.cleanupOptions[keyPath: keyPath] = enabled } }
            )) {
                settingLabel(title, symbol: symbol)
            }
            .toggleStyle(.switch)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var generalPage: some View {
        Form {
            Section {
                infoRow("Raccourci clavier", value: settings.config.hotkeyDisplaySummary(), symbol: "keyboard")
                infoRow("Modèle de transcription", value: selectedSpeechModel?.name ?? settings.config.modelSize,
                        symbol: "waveform")
                infoRow("Nettoyage du texte", value: settings.config.cleanupModel == nil ? "Désactivé" : "Activé",
                        symbol: "wand.and.stars")
            } header: {
                sectionHeading("Vue d'ensemble", symbol: "square.grid.2x2")
            } footer: {
                Text("La transcription et le nettoyage s'exécutent sur ce Mac.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    settingLabel("Dicter rapidement", symbol: "waveform")
                    Text(settings.config.toggleMode?.value == true
                         ? "Appuyez sur le raccourci pour commencer, puis appuyez de nouveau pour terminer."
                         : "Maintenez le raccourci pendant que vous parlez, puis relâchez-le.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    settingLabel("Retrouver la dernière dictée", symbol: "doc.on.clipboard")
                    Text("Choisissez « Copier la dernière dictée » dans le menu de Local-Echo pour récupérer le dernier texte.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    settingLabel("Changer de modèle", symbol: "cpu")
                    Text("Choisissez un modèle dans Transcription. Son téléchargement démarre si nécessaire.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeading("Conseils utiles", symbol: "lightbulb")
            }
        }
        .formStyle(.grouped)
    }

    private var transcriptionPage: some View {
        Form {
            ForEach(ModelCatalog.SizeCategory.allCases, id: \.self) { category in
                Section {
                    ForEach(ModelCatalog.speech.filter { $0.sizeCategory == category }, id: \.id) { model in
                        modelRow(model, selected: settings.config.modelSize == model.id) {
                            settings.change { $0.modelSize = model.id }
                        }
                    }
                } header: {
                    sectionHeading(categoryTitle(category), symbol: "waveform")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.config.spokenPunctuation?.value ?? false },
                    set: { enabled in settings.change { $0.spokenPunctuation = FlexBool(enabled) } }
                )) {
                    settingLabel("Interpréter la ponctuation prononcée", symbol: "text.quote")
                }
                .toggleStyle(.switch)
            } header: {
                sectionHeading("Ponctuation", symbol: "text.quote")
            } footer: {
                Text("Transforme les mots comme « virgule » et « point » en signes de ponctuation.")
            }

        }
        .formStyle(.grouped)
    }

    private func categoryTitle(_ category: ModelCatalog.SizeCategory) -> String {
        switch category {
        case .lightweight: "Modèles légers · moins de 1 Go"
        case .medium: "Modèles intermédiaires · 1 à 1,5 Go"
        case .heavy: "Modèles lourds · plus de 1,5 Go"
        }
    }

    private func modelRow(_ model: ModelCatalog.Model, selected: Bool,
                          onSelect: @escaping () -> Void) -> some View {
        let downloaded = ModelDownloader.modelExists(model.id)
        return Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(.primary)
                    .frame(width: 23)
                Text(model.name)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.approximateDownload)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Téléchargé : \(downloaded ? "oui" : "non")")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name), \(model.approximateDownload), téléchargé : \(downloaded ? "oui" : "non")")
    }

    private var cleanupPage: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.config.cleanupModel != nil },
                    set: { enabled in
                        settings.change { $0.cleanupModel = enabled ? ModelCatalog.cleanup.id : nil }
                    }
                )) {
                    settingLabel("Activer le nettoyage du texte", symbol: "sparkles")
                }
                .toggleStyle(.switch)
            } header: {
                sectionHeading("Après la transcription", symbol: "wand.and.stars")
            } footer: {
                Text("Le nettoyage s'applique après la reconnaissance vocale. Relisez les textes importants : une correction peut être erronée.")
            }

            Section {
                modelRow(ModelCatalog.cleanup, selected: settings.config.cleanupModel != nil) {
                    settings.change { $0.cleanupModel = ModelCatalog.cleanup.id }
                }
            } header: {
                sectionHeading("Modèle de nettoyage", symbol: "cpu")
            } footer: {
                Text("Un seul modèle de nettoyage est disponible actuellement. Utilisez l'interrupteur ci-dessus pour le désactiver.")
            }

            Section {
                Picker(selection: Binding(
                    get: { settings.config.cleanupOptions.formattingLevel },
                    set: { level in settings.change { $0.cleanupOptions.formattingLevel = level } }
                )) {
                    ForEach(CleanupFormattingLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                } label: {
                    settingLabel("Niveau de mise en forme", symbol: "textformat")
                }
                .pickerStyle(.segmented)
                Text(settings.config.cleanupOptions.formattingLevel.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeading("Mise en forme de la transcription", symbol: "text.alignleft")
            } footer: {
                Text("La ponctuation prononcée se règle séparément dans Transcription et s'applique avant le nettoyage.")
            }
            .disabled(settings.config.cleanupModel == nil)

            Section {
                cleanupSetting("Corriger les erreurs de transcription évidentes", symbol: "checkmark.seal",
                               detail: "Corrige un mot manifestement mal reconnu, sans réécrire la phrase.",
                               keyPath: \.correctRecognitionErrors)
            } header: {
                sectionHeading("Correction des mots", symbol: "text.badge.checkmark")
            }
            .disabled(settings.config.cleanupModel == nil)

            Section {
                cleanupSetting("Supprimer hésitations et répétitions", symbol: "text.badge.minus",
                               detail: "Ex. « Je, je voudrais euh partir » peut devenir « Je voudrais partir ».",
                               keyPath: \.removeFillers)
            } header: {
                sectionHeading("Options avancées", symbol: "slider.horizontal.3")
            }
            .disabled(settings.config.cleanupModel == nil)

            if settings.config.cleanupModel != nil && !settings.config.cleanupOptions.hasEdits {
                Text("Aucune correction n'est activée : la transcription restera telle quelle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var audioPage: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { settings.selectedDevice },
                    set: { settings.selectDevice($0) }
                )) {
                    Text("Microphone par défaut du système").tag("default")
                    ForEach(settings.inputDevices, id: \.id) { device in
                        Text(device.name).tag(String(device.id))
                    }
                } label: {
                    settingLabel("Microphone", symbol: "mic.fill")
                }
            } header: {
                sectionHeading("Entrée audio", symbol: "mic.fill")
            } footer: {
                Text("Le microphone par défaut suit les changements effectués dans Réglages Système.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.config.duckOtherAudioEnabled },
                    set: { enabled in
                        settings.change { $0.duckOtherAudioDuringRecording = FlexBool(enabled) }
                    }
                )) {
                    settingLabel("Réduire le son des autres applications", symbol: "speaker.wave.2.fill")
                }
                .toggleStyle(.switch)
                .disabled(settings.isRecording || !ProcessInfo.processInfo.isOperatingSystemAtLeast(
                    OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
                ))
            } header: {
                sectionHeading("Pendant l'enregistrement", symbol: "speaker.wave.2.fill")
            } footer: {
                Text("Disponible sur macOS 14 ou version ultérieure. Le volume est rétabli après l'enregistrement.")
            }
        }
        .formStyle(.grouped)
    }

    private var controlsPage: some View {
        Form {
            Section {
                Button {
                    settings.startShortcutCapture()
                } label: {
                    HStack {
                        settingLabel("Raccourci de dictée", symbol: "keyboard")
                        Spacer()
                        Text(settings.isCapturingShortcut ? "Appuyez sur les touches…" : settings.config.hotkeyDisplaySummary())
                            .foregroundStyle(settings.isCapturingShortcut ? .secondary : .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeading("Raccourci clavier", symbol: "keyboard.fill")
            } footer: {
                Text("Cliquez sur le raccourci, puis appuyez sur une touche ou une combinaison (par exemple ⌘ + ⇧ + Espace). Échap annule la saisie.")
            }

            Section {
                Picker(selection: Binding(
                    get: { settings.config.toggleMode?.value ?? false },
                    set: { enabled in settings.change { $0.toggleMode = FlexBool(enabled) } }
                )) {
                    Text("Maintenir pour dicter").tag(false)
                    Text("Appuyer pour démarrer / arrêter").tag(true)
                } label: {
                    settingLabel("Mode du raccourci", symbol: "hand.tap.fill")
                }
            } header: {
                sectionHeading("Déclenchement", symbol: "record.circle.fill")
            } footer: {
                Text("Avec « Maintenir », relâchez les touches pour terminer. Avec « Appuyer », un second appui arrête l'enregistrement.")
            }
        }
        .formStyle(.grouped)
    }

    private var advancedPage: some View {
        Form {
            Section {
                Button { settings.openConfiguration() } label: {
                    settingLabel("Ouvrir le fichier de configuration…", symbol: "doc.text")
                }
                Button { settings.revealConfiguration() } label: {
                    settingLabel("Afficher le fichier dans le Finder", symbol: "folder")
                }
                Button { settings.reloadConfiguration() } label: {
                    settingLabel("Recharger la configuration", symbol: "arrow.clockwise")
                }
            } header: {
                sectionHeading("Configuration", symbol: "doc.text")
            } footer: {
                Text(Config.configFile.path)
                    .textSelection(.enabled)
            }

            Section {
                Button(role: .destructive) {
                    settings.resetDefaults()
                } label: {
                    settingLabel("Rétablir les réglages par défaut", symbol: "arrow.counterclockwise")
                }
            } header: {
                sectionHeading("Réinitialisation", symbol: "arrow.counterclockwise")
            } footer: {
                Text("Rétablit les réglages initiaux après confirmation. Les modèles téléchargés restent sur ce Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutPage: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local-Echo").font(.title2.weight(.semibold))
                        Text("Dictée vocale locale pour macOS")
                            .foregroundStyle(.secondary)
                        Text("Version \(LocalEcho.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                infoRow("Version", value: LocalEcho.version, symbol: "number")
                infoRow("Compatibilité", value: "Apple Silicon · macOS 13 ou ultérieur",
                        symbol: "desktopcomputer")
                infoRow("Licence", value: "MIT", symbol: "doc.text")
            } header: {
                sectionHeading("L'application", symbol: "info.circle.fill")
            } footer: {
                Text("La transcription et le nettoyage du texte s'exécutent localement. Aucun compte n'est nécessaire.")
            }

            Section {
                Button {
                    if let url = URL(string: "https://github.com/NatanSlvdr/local-echo") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    settingLabel("Voir le code source", symbol: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                sectionHeading("Projet", symbol: "link")
            }
        }
        .formStyle(.grouped)
    }

    private var selectedSpeechModel: ModelCatalog.Model? {
        ModelCatalog.speechModel(settings.config.modelSize)
    }
}
