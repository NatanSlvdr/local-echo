import Foundation

/// Finds the executables and runtime files shipped in the app bundle, with fallbacks for source builds.
public enum BundledBinaries {
    public static var whisperServer: URL? {
        var candidates: [URL] = []
        if let directory = executableDirectory {
            candidates += [
                directory.appendingPathComponent("whisper-server"),
                directory.deletingLastPathComponent().appendingPathComponent("Local-Echo.app/Contents/MacOS/whisper-server"),
            ]
        }
        candidates += [FileManager.default.currentDirectoryPath + "/.build/whisper-server",
                       "/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .map { URL(fileURLWithPath: $0) }
        return firstExecutable(in: candidates)
    }

    static var uv: URL? {
        var candidates: [URL] = []
        if let directory = executableDirectory {
            candidates.append(directory.appendingPathComponent("uv"))
        }
        candidates += ["/opt/homebrew/bin/uv", "/usr/local/bin/uv",
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path]
            .map { URL(fileURLWithPath: $0) }
        return firstExecutable(in: candidates)
    }

    /// A file from Resources/ModelRuntime, in the app bundle or in a source checkout.
    static func modelRuntimeResource(_ name: String) -> URL {
        if let directory = executableDirectory {
            let bundled = directory.deletingLastPathComponent().appendingPathComponent("Resources/ModelRuntime/\(name)")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/ModelRuntime/\(name)")
    }

    private static var executableDirectory: URL? {
        Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    }

    private static func firstExecutable(in candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
