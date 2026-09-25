import SwiftUI

/// Records the dictation shortcut and chooses between holding and pressing it.
struct ShortcutPage: View {
    @ObservedObject var settings: SettingsStore

    private var hotkey: String { settings.config.hotkeyDisplaySummary() }
    private var toggleMode: Bool { settings.config.usesToggleMode }

    var body: some View {
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
                        settings.change { $0.usesToggleMode = false }
                    } illustration: {
                        ModeIllustration(key: hotkey, toggle: false, selected: !toggleMode)
                    }
                    ModeTile(title: "Appuyer",
                             detail: "Un appui démarre, un second appui termine. Pratique pour les longues dictées.",
                             selected: toggleMode) {
                        settings.change { $0.usesToggleMode = true }
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
}
