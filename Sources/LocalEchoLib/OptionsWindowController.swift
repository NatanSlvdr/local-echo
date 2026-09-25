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
        case .general: "vue d'ensemble dicter comment autorisations accessibilité microphone permission"
        case .transcription: "modèle reconnaissance vocale ponctuation taille téléchargement langue"
        case .cleanup: "nettoyage correction texte modèle mise en forme paragraphes liste hésitations"
        case .audio: "microphone entrée son volume baisser enregistrements conserver"
        case .controls: "enregistrement raccourci clavier touches combinaison maintenir appuyer fn globe"
        case .advanced: "configuration fichier ouvrir recharger réinitialiser défaut"
        case .about: "version licence compatibilité code source confidentialité"
        }
    }
}

// Mirrors System Settings: grouped forms, labeled groups, and short explanations only where they help.
private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Rechercher", text: Binding(
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
                    sidebarSection([.general, .transcription, .cleanup])
                    sidebarSection([.audio, .controls])
                    sidebarSection([.advanced, .about])
                    if !SettingsPage.allCases.contains(where: matches) {
                        Text("Aucun résultat")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
            }
            .tint(.blue)
            .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(page.title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(height: 44)
                Divider()

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var page: SettingsPage { settings.selection ?? .general }

    // MARK: - Sidebar

    @ViewBuilder
    private func sidebarSection(_ pages: [SettingsPage]) -> some View {
        let visible = pages.filter(matches)
        if !visible.isEmpty {
            Section {
                ForEach(visible, id: \.self) { sidebarItem($0) }
            }
        }
    }

    private func sidebarItem(_ page: SettingsPage) -> some View {
        HStack(spacing: 9) {
            IconBadge(symbol: page.symbol, color: page.color, size: 22)
            Text(page.title)
        }
        .padding(.vertical, 1)
        .tag(page)
    }

    private func matches(_ page: SettingsPage) -> Bool {
        let query = settings.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || page.title.localizedStandardContains(query)
            || page.searchTerms.localizedStandardContains(query)
    }

    // MARK: - Général

    private var hotkey: String { settings.config.hotkeyDisplaySummary() }
    private var toggleMode: Bool { settings.config.toggleMode?.value ?? false }

    private var generalPage: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local-Echo").font(.title3.weight(.semibold))
                        HStack(spacing: 5) {
                            Text(toggleMode ? "Appuyez sur" : "Maintenez")
                            KeyCap(hotkey)
                            Text(toggleMode ? "pour dicter, puis appuyez de nouveau." : "et parlez, puis relâchez.")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Comment dicter") {
                StepRow(number: 1, title: "Cliquez dans un champ de texte",
                        detail: "Dans n'importe quelle app : Mail, Notes, Messages, un navigateur…")
                StepRow(number: 2, title: toggleMode ? "Appuyez sur \(hotkey) et parlez" : "Maintenez \(hotkey) et parlez",
                        detail: "L'icône de Local-Echo s'anime dans la barre des menus pendant l'écoute.")
                StepRow(number: 3, title: toggleMode ? "Appuyez de nouveau sur \(hotkey)" : "Relâchez \(hotkey)",
                        detail: "Le texte apparaît à l'emplacement du curseur quelques instants plus tard.")
            }

            Section {
                PermissionRow(title: "Microphone", detail: "Pour entendre votre voix pendant la dictée.",
                              granted: settings.hasMicrophoneAccess, open: Permissions.openMicrophoneSettings)
                PermissionRow(title: "Accessibilité", detail: "Pour écrire le texte dicté dans l'app active.",
                              granted: settings.hasAccessibilityAccess, open: Permissions.openAccessibilitySettings)
            } header: {
                Text("Autorisations")
            } footer: {
                if !(settings.hasMicrophoneAccess && settings.hasAccessibilityAccess) {
                    Text("Activez Local-Echo dans la liste qui s'ouvre, puis revenez ici.")
                }
            }

            Section {
                NavigationRow(title: "Modèle de transcription", value: speechModelName) { go(.transcription) }
                NavigationRow(title: "Nettoyage du texte", value: cleanupSummary) { go(.cleanup) }
                NavigationRow(title: "Microphone", value: settings.selectedDeviceName) { go(.audio) }
                NavigationRow(title: "Raccourci", value: "\(hotkey) · \(toggleMode ? "Appuyer" : "Maintenir")") {
                    go(.controls)
                }
            } header: {
                Text("Réglages actuels")
            } footer: {
                Text("Astuce : si vous avez dicté sans champ de texte actif, choisissez « Copier la dernière dictée » dans le menu de Local-Echo.")
            }
        }
        .formStyle(.grouped)
    }

    private func go(_ page: SettingsPage) {
        settings.cancelShortcutCapture()
        settings.selection = page
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
            Section {
                ForEach(orderedSpeechModels, id: \.id) { model in
                    ChoiceRow(title: model.name, detail: Self.modelSummary(model.id),
                              trailing: downloadNote(model),
                              selected: settings.config.modelSize == model.id) {
                        settings.change { $0.modelSize = model.id }
                    }
                }
            } header: {
                Text("Modèle de transcription")
            } footer: {
                Text("Du plus léger au plus lourd. Un modèle non téléchargé se télécharge dès que vous le choisissez ; tout fonctionne ensuite hors ligne.")
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
                ExampleView(said: "hello comma how are you question mark", result: "hello, how are you?")
            } header: {
                Text("Ponctuation")
            } footer: {
                Text("Mots reconnus : comma, period, question mark, exclamation mark, colon, semicolon, new line, new paragraph, open quote, close quote.")
            }
        }
        .formStyle(.grouped)
    }

    private var orderedSpeechModels: [ModelCatalog.Model] {
        ModelCatalog.SizeCategory.allCases.flatMap { category in
            ModelCatalog.speech.filter { $0.sizeCategory == category }
        }
    }

    private func downloadNote(_ model: ModelCatalog.Model) -> String? {
        ModelDownloader.modelExists(model.id) ? nil : "À télécharger · \(model.approximateDownload)"
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

    private var cleanupPage: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { cleanupEnabled },
                    set: { enabled in
                        settings.change { $0.cleanupModel = enabled ? ModelCatalog.cleanup.id : nil }
                    }
                )) {
                    Text("Activer le nettoyage")
                    Text("Un petit modèle local relit chaque transcription pour en corriger la forme.")
                }
                .toggleStyle(.switch)
                LabeledContent("Modèle") {
                    Text(downloadNote(ModelCatalog.cleanup).map { "\(ModelCatalog.cleanup.name) · \($0)" }
                         ?? ModelCatalog.cleanup.name)
                }
            } header: {
                Text("Nettoyage après transcription")
            } footer: {
                Text("Relisez les textes importants : une correction automatique peut se tromper.")
            }

            Section {
                ForEach(CleanupFormattingLevel.allCases, id: \.self) { level in
                    ChoiceRow(title: level.title, detail: Self.levelSummary(level), trailing: nil,
                              selected: settings.config.cleanupOptions.formattingLevel == level) {
                        settings.change { $0.cleanupOptions.formattingLevel = level }
                    }
                }
                let example = Self.levelExample(settings.config.cleanupOptions.formattingLevel)
                ExampleView(said: example.said, result: example.result)
            } header: {
                Text("Niveau de mise en forme")
            }
            .disabled(!cleanupEnabled)

            Section {
                cleanupToggle("Corriger les erreurs évidentes",
                              detail: "Remplace un mot manifestement mal reconnu, sans réécrire la phrase. Ex. « un vert d'eau » → « un verre d'eau ».",
                              keyPath: \.correctRecognitionErrors)
                cleanupToggle("Supprimer hésitations et répétitions",
                              detail: "Ex. « Je, je voudrais euh partir » → « Je voudrais partir ».",
                              keyPath: \.removeFillers)
            } header: {
                Text("Corrections")
            } footer: {
                if cleanupEnabled && !settings.config.cleanupOptions.hasEdits {
                    Text("Aucune correction n'est activée : la transcription restera telle quelle.")
                }
            }
            .disabled(!cleanupEnabled)
        }
        .formStyle(.grouped)
    }

    private func cleanupToggle(_ title: String, detail: String,
                               keyPath: WritableKeyPath<CleanupOptions, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { settings.config.cleanupOptions[keyPath: keyPath] },
            set: { enabled in settings.change { $0.cleanupOptions[keyPath: keyPath] = enabled } }
        )) {
            Text(title)
            Text(detail)
        }
        .toggleStyle(.switch)
    }

    private static func levelSummary(_ level: CleanupFormattingLevel) -> String {
        switch level {
        case .none: "Garde la présentation telle quelle."
        case .light: "Ponctuation, majuscules et espaces."
        case .polished: "Phrases plus lisibles et paragraphes, sans listes."
        case .structured: "Paragraphes, et une liste quand vous énumérez des points."
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

    private var audioPage: some View {
        Form {
            Section {
                Picker("Microphone", selection: Binding(
                    get: { settings.selectedDevice },
                    set: { settings.selectDevice($0) }
                )) {
                    Text(settings.systemDefaultDeviceName.map { "Par défaut du système (\($0))" } ?? "Par défaut du système")
                        .tag("default")
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
                    Text("Ex. votre musique baisse pendant que vous parlez, puis retrouve son volume.")
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
                    get: { Config.effectiveMaxRecordings(settings.config.maxRecordings) },
                    set: { count in settings.change { $0.maxRecordings = count } }
                )) {
                    ForEach(recordingChoices, id: \.self) { count in
                        Text(count == 0 ? "Ne pas conserver" : "Les \(count) derniers").tag(count)
                    }
                } label: {
                    Text("Conserver les enregistrements")
                    Text("Pour retranscrire une ancienne dictée depuis le menu, dans « Enregistrements récents ».")
                }
                if Config.effectiveMaxRecordings(settings.config.maxRecordings) > 0 {
                    LabeledContent("Dossier") {
                        Button("Afficher dans le Finder") { settings.revealRecordings() }
                    }
                }
            } header: {
                Text("Enregistrements")
            } footer: {
                Text(Config.effectiveMaxRecordings(settings.config.maxRecordings) > 0
                     ? "Les fichiers audio restent sur ce Mac ; les plus anciens sont supprimés automatiquement."
                     : "L'audio de chaque dictée est supprimé dès que le texte est prêt.")
            }
        }
        .formStyle(.grouped)
    }

    private static var supportsDucking: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0))
    }

    private var recordingChoices: [Int] {
        let current = Config.effectiveMaxRecordings(settings.config.maxRecordings)
        let choices = [0, 5, 10, 25, 50, 100]
        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    // MARK: - Raccourci

    private var controlsPage: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if settings.isCapturingShortcut {
                            Text("Appuyez sur une touche…")
                                .foregroundStyle(.secondary)
                            Button("Annuler") { settings.cancelShortcutCapture() }
                        } else {
                            KeyCap(hotkey)
                            Button("Modifier…") { settings.startShortcutCapture() }
                        }
                    }
                } label: {
                    Text("Touche de dictée")
                    Text("Ex. Fn seule, ⌥ droite ou ⌃⌥Espace.")
                }
                if settings.config.hotkeys.contains(where: { $0.keyCode == 63 }) {
                    LabeledContent {
                        Button("Ouvrir Clavier…") { settings.openKeyboardSettings() }
                    } label: {
                        Text("Si Fn ouvre les emoji")
                        Text("Dans Réglages Système → Clavier, réglez « Appuyer sur 🌐 pour » sur « Ne rien faire ».")
                    }
                }
            } header: {
                Text("Raccourci de dictée")
            } footer: {
                Text("Une touche de modification seule, comme Fn ou ⌥ droite, fonctionne bien : elle ne gêne pas la saisie. Échap annule la modification.")
            }

            Section {
                ChoiceRow(title: "Maintenir pour dicter",
                          detail: "L'écoute dure tant que la touche est enfoncée. Idéal pour les phrases courtes.",
                          trailing: nil, selected: !toggleMode) {
                    settings.change { $0.toggleMode = FlexBool(false) }
                }
                ChoiceRow(title: "Appuyer pour démarrer / arrêter",
                          detail: "Un appui démarre, un second appui termine. Pratique pour les longues dictées.",
                          trailing: nil, selected: toggleMode) {
                    settings.change { $0.toggleMode = FlexBool(true) }
                }
            } header: {
                Text("Mode du raccourci")
            }
            .disabled(settings.isRecording)
        }
        .formStyle(.grouped)
    }

    // MARK: - Avancé

    private var advancedPage: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Button("Ouvrir") { settings.openConfiguration() }
                        Button("Afficher") { settings.revealConfiguration() }
                    }
                } label: {
                    Text("Modifier le fichier")
                    Text("Pour les options absentes de cette fenêtre, comme plusieurs raccourcis.")
                }
                LabeledContent {
                    Button("Recharger") { settings.reloadConfiguration() }
                } label: {
                    Text("Recharger la configuration")
                    Text("Applique les modifications faites dans le fichier.")
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
                    Text("Réglages par défaut")
                    Text("Les modèles téléchargés et les enregistrements sont conservés.")
                }
            } header: {
                Text("Réinitialisation")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - À propos

    private var aboutPage: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Local-Echo").font(.title2.weight(.semibold))
                        Text("Dictée vocale locale pour macOS")
                            .foregroundStyle(.secondary)
                        Text("Version \(LocalEcho.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Confidentialité") {
                HStack(spacing: 12) {
                    IconBadge(symbol: "lock.fill", color: .blue, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tout reste sur ce Mac")
                        Text("L'audio et le texte ne quittent jamais votre ordinateur. Aucun compte n'est nécessaire.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("L'application") {
                LabeledContent("Version", value: LocalEcho.version)
                LabeledContent("Compatibilité", value: "Mac Apple Silicon · macOS 13 ou ultérieur")
                LabeledContent("Licence", value: "MIT")
                LabeledContent("Code source") {
                    Button("Ouvrir sur GitHub") {
                        if let url = URL(string: "https://github.com/NatanSlvdr/local-echo") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Components

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

/// One option in a labeled group; the chosen one carries a checkmark, like the menu.
private struct ChoiceRow: View {
    let title: String
    let detail: String?
    let trailing: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "What you say" and "what you get", so a setting's effect is visible before trying it.
private struct ExampleView: View {
    let said: String
    let result: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("Vous dites", Text("« \(said) »").italic().foregroundStyle(.secondary))
            line("Résultat", Text(result))
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func line(_ label: String, _ text: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            text
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Autorisé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Autoriser…", action: open)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// A row that shows the current value and opens the page where it can be changed.
private struct NavigationRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
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
