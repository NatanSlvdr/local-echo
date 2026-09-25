import SwiftUI

/// Chooses the microphone, audio lowering during dictation, and how many recordings to keep.
struct AudioPage: View {
    @ObservedObject var settings: SettingsStore

    private var recordingsKept: Int { Config.effectiveMaxRecordings(settings.config.maxRecordings) }

    var body: some View {
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
                    set: { enabled in settings.change { $0.duckOtherAudioEnabled = enabled } }
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
}
