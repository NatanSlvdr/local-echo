import SwiftUI

// Mirrors System Settings: a searchable sidebar, a short page introduction, and grouped forms.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { settings.selection },
                set: { if let page = $0 { settings.show(page) } }
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
                case .general: GeneralPage(settings: settings)
                case .transcription: TranscriptionPage(settings: settings)
                case .cleanup: CleanupPage(settings: settings)
                case .audio: AudioPage(settings: settings)
                case .controls: ShortcutPage(settings: settings)
                case .advanced: AdvancedPage(settings: settings)
                case .about: AboutPage()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page.title)
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var page: SettingsPage { settings.selection ?? .general }

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
}
