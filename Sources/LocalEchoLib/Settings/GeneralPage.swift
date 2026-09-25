import SwiftUI

/// How to dictate, a place to try it, permissions, and a summary of the other pages.
struct GeneralPage: View {
    @ObservedObject var settings: SettingsStore

    private var hotkey: String { settings.config.hotkeyDisplaySummary() }
    private var toggleMode: Bool { settings.config.usesToggleMode }
    private var hasPermissions: Bool { settings.hasMicrophoneAccess && settings.hasAccessibilityAccess }

    var body: some View {
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
                NavigationRow(page: .transcription, title: "Modèle", value: speechModelName) {
                    settings.show(.transcription)
                }
                NavigationRow(page: .cleanup, title: "Nettoyage du texte", value: settings.config.cleanupSummary) {
                    settings.show(.cleanup)
                }
                NavigationRow(page: .audio, title: "Microphone", value: settings.selectedDeviceName) {
                    settings.show(.audio)
                }
                NavigationRow(page: .controls, title: "Raccourci", value: settings.config.shortcutSummary) {
                    settings.show(.controls)
                }
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
}
