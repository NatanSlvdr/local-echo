import SwiftUI

/// Turns transcript cleanup on or off and chooses its formatting level and corrections.
struct CleanupPage: View {
    @ObservedObject var settings: SettingsStore

    private var cleanupEnabled: Bool { settings.config.cleanupModel != nil }
    private var formattingLevel: CleanupFormattingLevel { settings.config.cleanupOptions.formattingLevel }

    var body: some View {
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
                    Text(ModelCatalog.cleanup.pendingDownload.map { "\(ModelCatalog.cleanup.name) · \($0) à télécharger" }
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
}
