import AppKit
import AVFoundation
@preconcurrency import ApplicationServices
import Foundation

struct Permissions {
    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone: granted")
            return true
        case .notDetermined:
            print("Microphone: requesting...")
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    print("Microphone: \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted)
                }
            }
        default:
            print("Microphone: denied — grant in System Settings → Privacy & Security → Microphone")
            return false
        }
    }

    static var hasMicrophoneAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reacts to activation changes and checks again periodically for Settings changes.
@MainActor
final class PermissionMonitor {
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var continuation: AsyncStream<Void>.Continuation?

    func waitUntil(_ authorized: @escaping @Sendable () -> Bool) async {
        guard !authorized() else { return }
        let stream = AsyncStream<Void> { continuation in
            self.continuation = continuation
            let workspace = NSWorkspace.shared.notificationCenter
            observers = [
                workspace.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.check(authorized) }
                },
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.check(authorized) }
                },
            ]
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.check(authorized) }
            }
            check(authorized)
        }
        defer { stop() }
        for await _ in stream {
            if authorized() { return }
        }
    }

    private func check(_ authorized: () -> Bool) {
        if authorized() { continuation?.yield(()) }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
    }
}
