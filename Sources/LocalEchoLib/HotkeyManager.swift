import AppKit
import Foundation

// Prevents shortcut recording in Settings from activating the current dictation hotkey.
final class ShortcutCaptureGate: @unchecked Sendable {
    static let shared = ShortcutCaptureGate()
    private let lock = NSLock()
    private var active = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }
}

class HotkeyManager {
    typealias GlobalMonitorInstaller = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias LocalMonitorInstaller = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let keyCode: UInt16
    private let requiredModifiers: UInt64
    private let addGlobalMonitor: GlobalMonitorInstaller
    private let addLocalMonitor: LocalMonitorInstaller
    private let removeMonitor: (Any) -> Void
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var modifierPressed = false
    private var keyPressed = false

    init(
        keyCode: UInt16,
        modifiers: UInt64 = 0,
        addGlobalMonitor: @escaping GlobalMonitorInstaller = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        addLocalMonitor: @escaping LocalMonitorInstaller = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
    }

    func start(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        globalMonitor = addGlobalMonitor(mask) { [weak self] event in
            self?.handleEvent(event)
        }
        localMonitor = addLocalMonitor(mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        modifierPressed = false
        keyPressed = false
    }

    private func handleEvent(_ event: NSEvent) {
        guard !ShortcutCaptureGate.shared.isActive else { return }
        if HotkeyConfig.modifierFlag(forKeyCode: keyCode) != nil {
            guard event.type == .flagsChanged else { return }
            guard event.keyCode == keyCode else { return }

            if modifierPressed {
                modifierPressed = false
                onKeyUp?()
            } else {
                guard hasRequiredModifiers(event) else { return }
                modifierPressed = true
                onKeyDown?()
            }
        } else {
            guard event.keyCode == keyCode else { return }
            if event.type == .keyDown {
                guard !keyPressed, hasRequiredModifiers(event) else { return }
                keyPressed = true
                onKeyDown?()
            } else if event.type == .keyUp, keyPressed {
                keyPressed = false
                onKeyUp?()
            }
        }
    }

    // Extra held modifiers are allowed, so Ctrl+Space still fires while Shift is down.
    private func hasRequiredModifiers(_ event: NSEvent) -> Bool {
        UInt64(event.modifierFlags.rawValue) & requiredModifiers == requiredModifiers
    }
}
