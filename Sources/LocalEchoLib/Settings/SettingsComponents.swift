import AppKit
import SwiftUI

struct HiddenSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

/// A white symbol on a colored rounded square, as in the System Settings sidebar.
struct IconBadge: View {
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
struct PageHeader: View {
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
struct RowLabel: View {
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

struct StatusPill: View {
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
struct KeyCap: View {
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
struct LargeKeyCap: View {
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

struct Pulsing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.variableColor.iterative)
        } else {
            content
        }
    }
}

/// One option in a labeled group; the chosen one carries a checkmark, like the menu.
struct ChoiceRow: View {
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
struct ModeTile<Illustration: View>: View {
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
struct ModeIllustration: View {
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

struct MiniKey: View {
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
struct ExampleCard: View {
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
struct TrialField: View {
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

struct PermissionRow: View {
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
struct NavigationRow: View {
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

extension ModelCatalog.Model {
    /// The approximate download size when the model is not installed yet.
    var pendingDownload: String? { isInstalled ? nil : approximateDownload }
}

extension ModelCatalog.Tint {
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        }
    }
}
