import SwiftUI

/// Version, privacy, and project information.
struct AboutPage: View {
    var body: some View {
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
