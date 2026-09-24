import Foundation

/// Creates an isolated MLX environment on first use, outside the signed app bundle.
public enum PythonRuntime {
    private static let lock = NSLock()
    private static var runtimeDir: URL { Config.configDir.appendingPathComponent("runtime") }
    private static var python: URL { runtimeDir.appendingPathComponent("venv/bin/python") }
    private static var stamp: URL { runtimeDir.appendingPathComponent("requirements.stamp") }

    public static func workerURL() -> URL { resourceURL("worker.py") }

    private static func resourceURL(_ name: String) -> URL {
        if let executable = Bundle.main.executableURL {
            let bundled = executable.deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/ModelRuntime/\(name)")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/ModelRuntime/\(name)")
    }

    public static func pythonURL() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let requirements = try Data(contentsOf: resourceURL("requirements.txt"))
        if FileManager.default.isExecutableFile(atPath: python.path),
           (try? Data(contentsOf: stamp)) == requirements { return python }
        guard let uv = findUV() else {
            throw ModelRuntimeError.workerFailed("uv is required for MLX models. Install uv, then rebuild the app.")
        }
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            try run(uv, ["venv", "--clear", "--python", "3.12", runtimeDir.appendingPathComponent("venv").path])
        }
        try run(uv, ["pip", "install", "--python", python.path, "-r", resourceURL("requirements.txt").path])
        try requirements.write(to: stamp, options: .atomic)
        return python
    }

    private static func findUV() -> URL? {
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("uv"))
        }
        candidates += ["/opt/homebrew/bin/uv", "/usr/local/bin/uv",
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path]
            .map { URL(fileURLWithPath: $0) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout
        try process.run()
        let (_, errorData) = ProcessOutput.read(stdout: stdout, stderr: stderr)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Runtime setup failed"
            throw ModelRuntimeError.workerFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
