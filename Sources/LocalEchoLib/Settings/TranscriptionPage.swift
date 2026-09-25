import SwiftUI

/// Chooses the speech model, lightest first, and shows which ones still need a download.
struct TranscriptionPage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            PageHeader(page: .transcription)

            Section {
                ForEach(ModelCatalog.speechByWeight, id: \.id) { model in
                    ChoiceRow(symbol: model.symbol, color: model.tint.color, title: model.name, tag: model.tag,
                              detail: model.summary, download: model.pendingDownload,
                              selected: settings.config.modelSize == model.id) {
                        settings.change { $0.modelSize = model.id }
                    }
                }
            } header: {
                Text("Modèle de transcription")
            } footer: {
                if ModelCatalog.speech.contains(where: { $0.pendingDownload != nil }) {
                    Text("Du plus léger au plus lourd. Un modèle marqué \(Image(systemName: "arrow.down.circle")) se télécharge dès que vous le choisissez ; tout fonctionne ensuite hors ligne.")
                } else {
                    Text("Du plus léger au plus lourd. Tous les modèles sont téléchargés et fonctionnent hors ligne.")
                }
            }
        }
    }
}
