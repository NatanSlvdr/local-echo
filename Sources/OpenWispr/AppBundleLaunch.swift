import AppKit
import Foundation

enum AppBundleLaunch {
    private static let bundleMarker = ".app/Contents/MacOS/"

    static func isExecutableInsideAppBundle(_ path: String) -> Bool {
        path.contains(bundleMarker)
    }

    static func findOpenWisprAppBundle() -> URL? {
        if let env = ProcessInfo.processInfo.environment["OPEN_WISPR_APP"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            let path = (env as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).resolvingSymlinksInPath()
        var dir = exec.deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("OpenWispr.app", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeApps = home.appendingPathComponent("Applications/OpenWispr.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeApps.path) { return homeApps }
        let system = URL(fileURLWithPath: "/Applications/OpenWispr.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: system.path) { return system }
        return nil
    }

    @discardableResult
    static func relaunchThroughAppBundleIfNeeded() -> Bool {
        let exec = ProcessInfo.processInfo.arguments[0]
        if isExecutableInsideAppBundle(exec) { return false }
        guard let appURL = findOpenWisprAppBundle() else { return false }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/open-wispr")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            fputs("Error: app bundle executable not found at \(executableURL.path)\n", stderr)
            return false
        }

        // Launch Services gives the app bundle its own privacy identity for microphone access.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-a", appURL.path, "--args", "start"]
        do {
            try launcher.run()
            launcher.waitUntilExit()
            if launcher.terminationStatus == 0 {
                print("Launched \(appURL.path) through Launch Services.")
                return true
            }
            fputs("Error: could not start OpenWispr.app (open exited with \(launcher.terminationStatus)).\n", stderr)
        } catch {
            fputs("Error: could not start OpenWispr.app: \(error.localizedDescription)\n", stderr)
        }
        return false
    }
}
