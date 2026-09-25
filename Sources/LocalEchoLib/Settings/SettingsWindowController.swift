import AppKit
import Combine
import SwiftUI

// Keeps the menu bar app's settings in a regular, native macOS window.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private var titleObserver: AnyCancellable?

    init(configStore: ConfigStore) {
        settings = SettingsStore(configStore: configStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        let content = NSHostingController(rootView: SettingsView(settings: settings))
        content.sizingOptions = []
        if #available(macOS 14.0, *) {
            // Lets the sidebar search field and page title live in the window toolbar, as in System Settings.
            content.sceneBridgingOptions = [.title, .toolbars]
        }
        window.contentViewController = content
        window.setContentSize(NSSize(width: 860, height: 660))
        window.title = SettingsPage.general.title
        window.toolbarStyle = .unified
        window.center()
        window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        titleObserver = settings.$selection.sink { [weak window] page in
            window?.title = (page ?? .general).title
        }
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
        settings.refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        settings.cancelShortcutCapture()
    }

    /// Reads devices and permissions again before the window is shown.
    func refresh(isRecording: Bool) {
        settings.setRecording(isRecording)
        settings.refresh()
    }

    func setRecording(_ isRecording: Bool) {
        settings.setRecording(isRecording)
    }

    func show(page: SettingsPage) {
        settings.searchText = ""
        settings.show(page)
    }
}
