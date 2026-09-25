import AppKit
import Combine
import SwiftUI

// Keeps the menu bar app's settings in a regular, native macOS window.
final class OptionsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private var titleObserver: AnyCancellable?

    init(onConfigChange: @escaping (Config) -> Void) {
        settings = SettingsStore(onConfigChange: onConfigChange)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        let content = NSHostingController(rootView: SettingsView(settings: settings))
        content.sizingOptions = []
        if #available(macOS 14.0, *) {
            // Lets the sidebar search field and page title live in the window toolbar, as in System Settings.
            content.sceneBridgingOptions = [.title, .toolbars]
        }
        window.contentViewController = content
        window.setContentSize(NSSize(width: 860, height: 660))
        window.title = SettingsPage.general.title
        window.toolbarStyle = .unified
        window.center()
        window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        titleObserver = settings.$selection.sink { [weak window] page in
            window?.title = (page ?? .general).title
        }
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

    func windowDidBecomeKey(_ notification: Notification) {
        settings.refreshPermissions()
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
    /// Text typed or dictated into the "Essayer" field; kept while the window stays open.
    @Published var trialText = ""
    @Published private(set) var isCapturingShortcut = false
    @Published private(set) var hasMicrophoneAccess = Permissions.hasMicrophoneAccess
    @Published private(set) var hasAccessibilityAccess = AXIsProcessTrusted()
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
        refreshPermissions()
    }

    func refreshPermissions() {
        hasMicrophoneAccess = Permissions.hasMicrophoneAccess
        hasAccessibilityAccess = AXIsProcessTrusted()
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

    var systemDefaultDeviceName: String? {
        inputDevices.first(where: \.isDefault)?.name
    }

    var selectedDeviceName: String {
        inputDevices.first { String($0.id) == selectedDevice }?.name
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
        case .controls: "Raccourci"
        case .advanced: "Avancé"
        case .about: "À propos"
        }
    }

    /// One sentence at the top of the page that says what the page is for.
    var summary: String {
        switch self {
        case .general: "Dictée vocale locale pour macOS."
        case .transcription: "Le modèle qui transforme votre voix en texte. Il fonctionne entièrement sur ce Mac, même hors ligne."
        case .cleanup: "Un petit modèle local relit chaque transcription pour en corriger la forme, sans changer ce que vous avez dit."
        case .audio: "Le micro utilisé pour la dictée, et ce que fait votre Mac pendant que vous parlez."
        case .controls: "La touche qui lance la dictée, dans n'importe quelle app."
        case .advanced: "Le fichier de configuration pour les options absentes de cette fenêtre, et le retour aux réglages d'origine."
        case .about: "Dictée vocale locale pour macOS."
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
        case .general: "vue d'ensemble dicter essayer tester comment autorisations accessibilité microphone permission"
        case .transcription: "modèle reconnaissance vocale ponctuation taille téléchargement langue"
        case .cleanup: "nettoyage correction texte modèle mise en forme paragraphes liste hésitations"
        case .audio: "microphone entrée son volume baisser enregistrements conserver"
        case .controls: "enregistrement raccourci clavier touches combinaison maintenir appuyer fn globe"
        case .advanced: "configuration fichier ouvrir recharger réinitialiser défaut"
        case .about: "version licence compatibilité code source confidentialité"
        }
    }
}

// Mirrors System Settings: a searchable sidebar, a short page introduction, and grouped forms.
private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { settings.selection },
                set: { if let page = $0 { go(page) } }
            )) {
                sidebarSection([.general, .transcription, .cleanup])
                sidebarSection([.audio, .controls])
                sidebarSection([.advanced, .about])
                if !SettingsPage.allCases.contains(where: matches) {
                    Text("Aucun résultat")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $settings.searchText, placement: .sidebar, prompt: "Rechercher")
            .modifier(HiddenSidebarToggle())
            .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 300)
        } detail: {
            Group {
                switch page {
                case .general: generalPage
                case .transcription: transcriptionPage
                case .cleanup: cleanupPage
                case .audio: audioPage
                case .controls: controlsPage
                case .advanced: advancedPage
                case .about: aboutPage
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page.title)
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var page: SettingsPage { settings.selection ?? .general }

    private func go(_ page: SettingsPage) {
        settings.cancelShortcutCapture()
        settings.selection = page
    }

    // MARK: - Sidebar

    @ViewBuilder
    private func sidebarSection(_ pages: [SettingsPage]) -> some View {
        let visible = pages.filter(matches)
        if !visible.isEmpty {
            Section {
                ForEach(visible, id: \.self) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        IconBadge(symbol: page.symbol, color: page.color, size: 20)
                    }
                    .tag(page)
                }
            }
        }
    }

    private func matches(_ page: SettingsPage) -> Bool {
        let query = settings.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || page.title.localizedStandardContains(query)
            || page.searchTerms.localizedStandardContains(query)
    }

    // MARK: - Général

    private var hotkey: String { settings.config.hotkeyDisplaySummary() }
    private var toggleMode: Bool { settings.config.toggleMode?.value ?? false }
    private var hasPermissions: Bool { settings.hasMicrophoneAccess && settings.hasAccessibilityAccess }

    private var generalPage: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local-Echo").font(.title2.weight(.bold))
                        HStack(spacing: 5) {
                            Text(toggleMode ? "Appuyez sur" : "Maintenez")
                            KeyCap(hotkey)
                            Text(toggleMode ? "pour dicter, puis appuyez de nouveau." : "et parlez, puis relâchez.")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    status
                }
                .padding(.vertical, 8)
            }

            Section {
                TrialField(text: $settings.trialText,
                           prompt: toggleMode ? "Cliquez ici, appuyez sur \(hotkey) et parlez…"
                                              : "Cliquez ici, maintenez \(hotkey) et parlez…",
                           isRecording: settings.isRecording)
            } header: {
                Text("Essayer")
            } footer: {
                Text("La dictée fonctionne de la même façon dans toutes vos apps : le texte s'écrit là où se trouve le curseur.")
            }

            Section {
                PermissionRow(symbol: "mic.fill", color: .orange, title: "Microphone",
                              detail: "Pour entendre votre voix pendant la dictée.",
                              granted: settings.hasMicrophoneAccess, open: Permissions.openMicrophoneSettings)
                PermissionRow(symbol: "accessibility", color: .blue, title: "Accessibilité",
                              detail: "Pour écrire le texte dicté dans l'app active.",
                              granted: settings.hasAccessibilityAccess, open: Permissions.openAccessibilitySettings)
            } header: {
                Text("Autorisations")
            } footer: {
                if !hasPermissions {
                    Text("Activez Local-Echo dans la liste qui s'ouvre, puis revenez ici.")
                }
            }

            Section {
                NavigationRow(page: .transcription, title: "Modèle", value: speechModelName) { go(.transcription) }
                NavigationRow(page: .cleanup, title: "Nettoyage du texte", value: cleanupSummary) { go(.cleanup) }
                NavigationRow(page: .audio, title: "Microphone", value: settings.selectedDeviceName) { go(.audio) }
                NavigationRow(page: .controls, title: "Raccourci",
                              value: "\(hotkey) · \(toggleMode ? "Appuyer" : "Maintenir")") { go(.controls) }
            } header: {
                Text("Vos réglages")
            } footer: {
                Text("Astuce : si vous avez dicté sans champ de texte actif, choisissez « Copier la dernière dictée » dans le menu de Local-Echo.")
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if settings.isRecording {
            StatusPill(text: "Écoute…", color: .red)
        } else if hasPermissions {
            StatusPill(text: "Prêt", color: .green)
        } else {
            StatusPill(text: "Autorisations requises", color: .orange)
        }
    }

    private var speechModelName: String {
        ModelCatalog.speechModel(settings.config.modelSize)?.name ?? settings.config.modelSize
    }

    private var cleanupSummary: String {
        settings.config.cleanupModel == nil
            ? "Désactivé"
            : "Mise en forme \(settings.config.cleanupOptions.formattingLevel.title.lowercased())"
    }

    // MARK: - Transcription

    private var transcriptionPage: some View {
        Form {
            PageHeader(page: .transcription)

            Section {
                ForEach(orderedSpeechModels, id: \.id) { model in
                    let style = Self.modelStyle(model.id)
                    ChoiceRow(symbol: style.symbol, color: style.color, title: model.name, tag: style.tag,
                              detail: Self.modelSummary(model.id), download: downloadSize(model),
                              selected: settings.config.modelSize == model.id) {
                        settings.change { $0.modelSize = model.id }
                    }
                }
            } header: {
                Text("Modèle de transcription")
            } footer: {
                if orderedSpeechModels.contains(where: { downloadSize($0) != nil }) {
                    Text("Du plus léger au plus lourd. Un modèle marqué \(Image(systemName: "arrow.down.circle")) se télécharge dès que vous le choisissez ; tout fonctionne ensuite hors ligne.")
                } else {
                    Text("Du plus léger au plus lourd. Tous les modèles sont téléchargés et fonctionnent hors ligne.")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.config.spokenPunctuation?.value ?? false },
                    set: { enabled in settings.change { $0.spokenPunctuation = FlexBool(enabled) } }
                )) {
                    Text("Interpréter la ponctuation dictée")
                    Text("Retire la ponctuation automatique et n'ajoute que celle que vous prononcez, en anglais.")
                }
                .toggleStyle(.switch)
                ExampleCard(said: "hello comma how are you question mark", result: "hello, how are you?")
            } header: {
                Text("Ponctuation")
            } footer: {
                Text("Mots reconnus : comma, period, question mark, exclamation mark, colon, semicolon, new line, new paragraph, open quote, close quote.")
            }
        }
    }

    private var orderedSpeechModels: [ModelCatalog.Model] {
        ModelCatalog.SizeCategory.allCases.flatMap { category in
            ModelCatalog.speech.filter { $0.sizeCategory == category }
        }
    }

    private func downloadSize(_ model: ModelCatalog.Model) -> String? {
        ModelDownloader.modelExists(model.id) ? nil : model.approximateDownload
    }

    private static func modelStyle(_ id: String) -> (symbol: String, color: Color, tag: String?) {
        switch id {
        case "parakeet-tdt-v3-mixed": ("hare.fill", .green, "Rapide")
        case "qwen3-asr-1.7b-4bit": ("scalemass.fill", .blue, "Équilibré")
        case "qwen3-asr-1.7b-8bit": ("scope", .purple, "Précis")
        case "large-v3-turbo": ("globe", .teal, "Multilingue")
        default: ("waveform", .gray, nil)
        }
    }

    private static func modelSummary(_ id: String) -> String? {
        switch id {
        case "parakeet-tdt-v3-mixed": "Le plus rapide et le plus léger. 25 langues européennes, dont le français."
        case "qwen3-asr-1.7b-4bit": "Bon équilibre entre précision, vitesse et taille."
        case "qwen3-asr-1.7b-8bit": "La meilleure précision de Qwen3, au prix d'un modèle plus lourd."
        case "large-v3-turbo": "Polyvalent et éprouvé, reconnaît un très grand nombre de langues."
        default: nil
        }
    }

    // MARK: - Nettoyage

    private var cleanupEnabled: Bool { settings.config.cleanupModel != nil }
    private var formattingLevel: CleanupFormattingLevel { settings.config.cleanupOptions.formattingLevel }

    private var cleanupPage: some View {
        Form {
            PageHeader(page: .cleanup)

            Section {
                Toggle(isOn: Binding(
                    get: { cleanupEnabled },
                    set: { enabled in
                        settings.change { $0.cleanupModel = enabled ? ModelCatalog.cleanup.id : nil }
                    }
                )) {
                    Text("Nettoyer les transcriptions")
                    Text(downloadSize(ModelCatalog.cleanup).map { "\(ModelCatalog.cleanup.name) · \($0) à télécharger" }
                         ?? ModelCatalog.cleanup.name)
                }
                .toggleStyle(.switch)
            } footer: {
                Text("Relisez les textes importants : une correction automatique peut se tromper.")
            }

            Section {
                Picker("Niveau", selection: Binding(
                    get: { formattingLevel },
                    set: { level in settings.change { $0.cleanupOptions.formattingLevel = level } }
                )) {
                    ForEach(CleanupFormattingLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.levelSummary(formattingLevel))
                        .foregroundStyle(.secondary)
                    let example = Self.levelExample(formattingLevel)
                    ExampleCard(said: example.said, result: example.result)
                }
            } header: {
                Text("Mise en forme")
            }
            .disabled(!cleanupEnabled)

            Section {
                cleanupToggle(\.correctRecognitionErrors) {
                    Text("Corriger les erreurs évidentes")
                    Text("Remplace un mot manifestement mal reconnu, sans réécrire la phrase : « un \(Text("vert").strikethrough()) \(Text("verre").foregroundColor(.accentColor)) d'eau ».")
                }
                cleanupToggle(\.removeFillers) {
                    Text("Supprimer hésitations et répétitions")
                    Text("« \(Text("Je, euh,").strikethrough()) je voudrais partir » devient « Je voudrais partir ».")
                }
            } header: {
                Text("Corrections")
            } footer: {
                if cleanupEnabled && !settings.config.cleanupOptions.hasEdits {
                    Text("Aucune correction n'est activée : la transcription restera telle quelle.")
                }
            }
            .disabled(!cleanupEnabled)
        }
    }

    private func cleanupToggle(_ keyPath: WritableKeyPath<CleanupOptions, Bool>,
                               @ViewBuilder label: () -> some View) -> some View {
        Toggle(isOn: Binding(
            get: { settings.config.cleanupOptions[keyPath: keyPath] },
            set: { enabled in settings.change { $0.cleanupOptions[keyPath: keyPath] = enabled } }
        ), label: label)
        .toggleStyle(.switch)
    }

    private static func levelSummary(_ level: CleanupFormattingLevel) -> String {
        switch level {
        case .none: "Garde la présentation telle quelle. Les corrections ci-dessous restent possibles."
        case .light: "Ajuste la ponctuation, les majuscules et les espaces."
        case .polished: "Rend les phrases plus lisibles et sépare les idées en paragraphes, sans listes."
        case .structured: "Crée des paragraphes, et une liste quand vous énumérez clairement des points."
        }
    }

    private static func levelExample(_ level: CleanupFormattingLevel) -> (said: String, result: String) {
        switch level {
        case .none:
            ("bonjour comment ça va", "bonjour comment ça va")
        case .light:
            ("bonjour comment ça va", "Bonjour, comment ça va ?")
        case .polished:
            ("merci pour la réunion d'hier sinon vendredi je serai en retard",
             "Merci pour la réunion d'hier.\n\nSinon, vendredi, je serai en retard.")
        case .structured:
            ("pour ce soir il faut premièrement du pain deuxièmement du lait",
             "Pour ce soir, il faut :\n- du pain ;\n- du lait.")
        }
    }

    // MARK: - Audio

    private var recordingsKept: Int { Config.effectiveMaxRecordings(settings.config.maxRecordings) }

    private var audioPage: some View {
        Form {
            PageHeader(page: .audio)

            Section {
                Picker("Microphone", selection: Binding(
                    get: { settings.selectedDevice },
                    set: { settings.selectDevice($0) }
                )) {
                    Text(settings.systemDefaultDeviceName.map { "Par défaut du système (\($0))" } ?? "Par défaut du système")
                        .tag("default")
                    Divider()
                    ForEach(settings.inputDevices, id: \.id) { device in
                        Text(device.name).tag(String(device.id))
                    }
                }
            } header: {
                Text("Entrée audio")
            } footer: {
                Text("« Par défaut du système » suit le micro choisi dans Réglages Système → Son, par exemple quand vous branchez des écouteurs.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.config.duckOtherAudioEnabled },
                    set: { enabled in
                        settings.change { $0.duckOtherAudioDuringRecording = FlexBool(enabled) }
                    }
                )) {
                    Text("Baisser le son des autres apps")
                    Text("Votre musique ou une vidéo baisse pendant que vous parlez, puis retrouve son volume.")
                }
                .toggleStyle(.switch)
                .disabled(settings.isRecording || !Self.supportsDucking)
            } header: {
                Text("Pendant la dictée")
            } footer: {
                if !Self.supportsDucking {
                    Text("Nécessite macOS 14 ou version ultérieure.")
                }
            }

            Section {
                Picker(selection: Binding(
                    get: { recordingsKept },
                    set: { count in settings.change { $0.maxRecordings = count } }
                )) {
                    ForEach(recordingChoices, id: \.self) { count in
                        Text(count == 0 ? "Ne pas conserver" : "Les \(count) derniers").tag(count)
                    }
                } label: {
                    Text("Conserver les enregistrements")
                    Text("Pour retranscrire une ancienne dictée depuis « Enregistrements récents », dans le menu.")
                }
                if recordingsKept > 0 {
                    LabeledContent("Dossier") {
                        Button("Afficher dans le Finder") { settings.revealRecordings() }
                    }
                }
            } header: {
                Text("Enregistrements")
            } footer: {
                Text(recordingsKept > 0
                     ? "Les fichiers audio restent sur ce Mac ; les plus anciens sont supprimés automatiquement."
                     : "L'audio de chaque dictée est supprimé dès que le texte est prêt.")
            }
        }
    }

    private static var supportsDucking: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0))
    }

    private var recordingChoices: [Int] {
        let choices = [0, 5, 10, 25, 50, 100]
        return choices.contains(recordingsKept) ? choices : (choices + [recordingsKept]).sorted()
    }

    // MARK: - Raccourci

    private var controlsPage: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    LargeKeyCap(text: settings.isCapturingShortcut ? "" : hotkey,
                                isListening: settings.isCapturingShortcut)
                    VStack(spacing: 3) {
                        Text(settings.isCapturingShortcut ? "Appuyez sur la touche ou la combinaison voulue"
                                                          : "Raccourci de dictée")
                            .font(.headline)
                        Text(settings.isCapturingShortcut
                             ? "Échap pour annuler."
                             : "Une touche de modification seule, comme Fn ou ⌥ droite, ne gêne pas la saisie.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if settings.isCapturingShortcut {
                        Button("Annuler") { settings.cancelShortcutCapture() }
                    } else {
                        Button("Modifier le raccourci…") { settings.startShortcutCapture() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    ModeTile(title: "Maintenir",
                             detail: "L'écoute dure tant que la touche est enfoncée. Idéal pour les phrases courtes.",
                             selected: !toggleMode) {
                        settings.change { $0.toggleMode = FlexBool(false) }
                    } illustration: {
                        ModeIllustration(key: hotkey, toggle: false, selected: !toggleMode)
                    }
                    ModeTile(title: "Appuyer",
                             detail: "Un appui démarre, un second appui termine. Pratique pour les longues dictées.",
                             selected: toggleMode) {
                        settings.change { $0.toggleMode = FlexBool(true) }
                    } illustration: {
                        ModeIllustration(key: hotkey, toggle: true, selected: toggleMode)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Mode")
            }
            .disabled(settings.isRecording)

            if settings.config.hotkeys.contains(where: { $0.keyCode == 63 }) {
                Section {
                    LabeledContent {
                        Button("Ouvrir Clavier…") { settings.openKeyboardSettings() }
                    } label: {
                        RowLabel(symbol: "globe", color: .blue, title: "Si Fn ouvre les emoji",
                                 detail: "Dans Réglages Système → Clavier, réglez « Appuyer sur 🌐 pour » sur « Ne rien faire ».")
                    }
                }
            }
        }
    }

    // MARK: - Avancé

    private var advancedPage: some View {
        Form {
            PageHeader(page: .advanced)

            Section {
                LabeledContent {
                    HStack {
                        Button("Ouvrir") { settings.openConfiguration() }
                        Button("Afficher") { settings.revealConfiguration() }
                    }
                } label: {
                    RowLabel(symbol: "doc.text.fill", color: .gray, title: "Modifier le fichier",
                             detail: "Par exemple pour définir plusieurs raccourcis.")
                }
                LabeledContent {
                    Button("Recharger") { settings.reloadConfiguration() }
                } label: {
                    RowLabel(symbol: "arrow.clockwise", color: .blue, title: "Recharger la configuration",
                             detail: "Applique les modifications faites dans le fichier.")
                }
            } header: {
                Text("Fichier de configuration")
            } footer: {
                Text(Config.configFile.path)
                    .textSelection(.enabled)
            }

            Section {
                LabeledContent {
                    Button("Rétablir…", role: .destructive) { settings.resetDefaults() }
                } label: {
                    RowLabel(symbol: "arrow.counterclockwise", color: .red, title: "Réglages par défaut",
                             detail: "Les modèles téléchargés et les enregistrements sont conservés.")
                }
            } header: {
                Text("Réinitialisation")
            }
        }
    }

    // MARK: - À propos

    private var aboutPage: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                    Text("Local-Echo").font(.title.weight(.bold))
                    Text("Version \(LocalEcho.version)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(SettingsPage.about.summary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                RowLabel(symbol: "lock.fill", color: .blue, title: "Tout reste sur ce Mac",
                         detail: "L'audio et le texte ne quittent jamais votre ordinateur. Aucun compte n'est nécessaire.")
            } header: {
                Text("Confidentialité")
            }

            Section {
                LabeledContent("Compatibilité", value: "Mac Apple Silicon · macOS 13 ou ultérieur")
                LabeledContent("Licence", value: "MIT")
                LabeledContent("Code source") {
                    Link(destination: URL(string: "https://github.com/NatanSlvdr/local-echo")!) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("L'application")
            }
        }
    }
}

// MARK: - Components

private struct HiddenSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

/// A white symbol on a colored rounded square, as in the System Settings sidebar.
private struct IconBadge: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Opens a page with its icon, title, and purpose, like the top of System Settings panes.
private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        Section {
            VStack(spacing: 8) {
                IconBadge(symbol: page.symbol, color: page.color, size: 48)
                Text(page.title)
                    .font(.title2.weight(.bold))
                Text(page.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A row title with an icon badge and an optional explanation.
private struct RowLabel: View {
    let symbol: String
    let color: Color
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Shows a shortcut the way macOS draws keys in settings.
private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.tertiary, lineWidth: 0.5))
            .accessibilityLabel("Raccourci \(text)")
    }
}

/// The dictation shortcut drawn as a physical key; it pulses while waiting for a new one.
private struct LargeKeyCap: View {
    let text: String
    let isListening: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if isListening {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .modifier(Pulsing())
            } else {
                Text(text)
                    .font(.system(size: 26, weight: .medium))
            }
        }
        .frame(minWidth: 72, minHeight: 64)
        .padding(.horizontal, 16)
        .background(shape.fill(Color(nsColor: .controlColor)))
        .overlay(shape.strokeBorder(isListening ? Color.accentColor : Color.primary.opacity(0.15),
                                    lineWidth: isListening ? 2 : 1))
        .shadow(color: .black.opacity(0.18), radius: 0.5, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isListening)
        .accessibilityLabel(isListening ? "En attente d'un nouveau raccourci" : "Raccourci \(text)")
    }
}

private struct Pulsing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.variableColor.iterative)
        } else {
            content
        }
    }
}

/// One option in a labeled group; the chosen one carries a checkmark, like the menu.
private struct ChoiceRow: View {
    let symbol: String
    let color: Color
    let title: String
    let tag: String?
    let detail: String?
    let download: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, color: color, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                        if let tag {
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(color.opacity(0.15), in: Capsule())
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if let download {
                    Label(download, systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("À télécharger")
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A large, illustrated choice, like the Appearance options in System Settings.
private struct ModeTile<Illustration: View>: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let illustration: () -> Illustration

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                illustration()
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(shape.fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
                    .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1),
                                                lineWidth: selected ? 2 : 1))
                Text(title)
                    .fontWeight(selected ? .semibold : .regular)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Shows when Local-Echo listens: while the key is held, or between two presses.
private struct ModeIllustration: View {
    let key: String
    let toggle: Bool
    let selected: Bool

    var body: some View {
        let tint = selected ? Color.accentColor : Color.secondary
        HStack(spacing: 6) {
            if toggle {
                MiniKey(text: key, tint: tint)
                listening(tint)
                MiniKey(text: key, tint: tint)
            } else {
                HStack(spacing: 6) {
                    MiniKey(text: key, tint: tint)
                    listening(tint)
                        .padding(.trailing, 6)
                }
                .padding(3)
                .background(Capsule().fill(tint.opacity(0.18)))
            }
        }
        .accessibilityHidden(true)
    }

    private func listening(_ tint: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "waveform")
            Image(systemName: "waveform")
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(tint)
    }
}

private struct MiniKey: View {
    let text: String
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(shape.fill(Color(nsColor: .controlColor)))
            .overlay(shape.strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 1)
    }
}

/// "What you say" next to "what gets written", so a setting's effect is visible before trying it.
private struct ExampleCard: View {
    let said: String
    let result: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .center, spacing: 10) {
            panel("Vous dites", symbol: "waveform") {
                Text("« \(said) »")
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .background(shape.fill(Color.primary.opacity(0.05)))

            Image(systemName: "arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)

            panel("Local-Echo écrit", symbol: "text.cursor") {
                Text(result)
                    .id(result)
                    .transition(.opacity)
            }
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: result)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func panel(_ title: String, symbol: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}

/// A field in the settings window where dictation can be tried right away.
private struct TrialField: View {
    @Binding var text: String
    let prompt: String
    let isRecording: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $text, prompt: Text(prompt), axis: .vertical) {
                Text("Zone d'essai")
            }
            .textFieldStyle(.plain)
            .labelsHidden()
            .lineLimit(3...8)
            .focused($focused)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay(shape.strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                                        lineWidth: focused ? 2 : 1))
            .contentShape(shape)
            .onTapGesture { focused = true }

            HStack {
                if isRecording {
                    Label("Écoute en cours…", systemImage: "waveform")
                        .foregroundStyle(.red)
                } else if focused {
                    Label("Prêt, vous pouvez parler", systemImage: "checkmark.circle")
                }
                Spacer()
                if !text.isEmpty {
                    Button("Effacer") { text = "" }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Autorisé")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Autoriser…", action: open)
                    .buttonStyle(.borderedProminent)
            }
        } label: {
            RowLabel(symbol: symbol, color: color, title: title, detail: detail)
        }
    }
}

/// A row that shows the current value and opens the page where it can be changed.
private struct NavigationRow: View {
    let page: SettingsPage
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                RowLabel(symbol: page.symbol, color: page.color, title: title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
