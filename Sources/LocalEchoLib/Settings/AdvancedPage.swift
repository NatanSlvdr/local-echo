import SwiftUI

/// Opens or reloads the configuration file and restores default settings.
struct AdvancedPage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
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
}
