import Foundation

public final class Transcriber: Sendable {
    private let modelSize: String
    private let whisperPrompt: String?

    public init(modelSize: String = "large-v3-turbo", whisperPrompt: String? = nil) {
        self.modelSize = modelSize
        self.whisperPrompt = whisperPrompt
    }

    public func transcribe(audioURL: URL) throws -> String {
        guard let model = ModelCatalog.speechModel(modelSize) else {
            throw TranscriberError.modelNotFound(modelSize)
        }
        return try ModelRuntime.shared.transcribe(model: model, audioURL: audioURL,
                                                  prompt: model.backend == .whisper ? effectiveWhisperPrompt : nil)
    }

    private var effectiveWhisperPrompt: String? {
        guard let whisperPrompt else { return nil }
        return whisperPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : whisperPrompt
    }

    private static let knownMarkers: Set<String> = [
        "BLANK_AUDIO", "blank_audio",
        "Music", "MUSIC", "music",
        "Applause", "APPLAUSE", "applause",
        "Laughter", "LAUGHTER", "laughter",
        "silence", "Silence", "SILENCE",
        "SOUND", "Sound", "sound",
        "NOISE", "Noise", "noise",
        "INAUDIBLE", "inaudible",
    ]

    private static let markerRegex = try! NSRegularExpression(
        pattern: "[\\[\\(]\\s*([^\\]\\)]+?)\\s*[\\]\\)]"
    )

    public static func stripWhisperMarkers(_ text: String) -> String {
        let nsText = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result = text
        for match in matches.reversed() {
            let innerRange = match.range(at: 1)
            let inner = nsText.substring(with: innerRange)
            if knownMarkers.contains(inner) {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: "")
            }
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func findWhisperBinary() -> String? {
        if let executable = Bundle.main.executableURL,
           let bundled = bundledWhisperPath(forExecutable: executable) {
            return bundled
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["whisper-cli"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()

        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let result, !result.isEmpty {
            return result
        }

        return nil
    }

    public static func findWhisperServerBinary() -> String? {
        if let executable = Bundle.main.executableURL {
            let directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
            let candidates = [directory.appendingPathComponent("whisper-server"),
                              directory.deletingLastPathComponent().appendingPathComponent("Local-Echo.app/Contents/MacOS/whisper-server")]
            if let bundled = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
                return bundled.path
            }
        }
        let candidates = [FileManager.default.currentDirectoryPath + "/.build/whisper-server",
                          "/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    // The app bundle carries its own transcriber; source builds can use PATH.
    static func bundledWhisperPath(forExecutable executable: URL) -> String? {
        let directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = [
            directory.appendingPathComponent("whisper-cli"),
            directory.deletingLastPathComponent().appendingPathComponent("Local-Echo.app/Contents/MacOS/whisper-cli"),
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })?.path
    }

    public static func modelExists(modelSize: String) -> Bool {
        return ModelDownloader.modelExists(modelSize)
    }

    static func findModel(modelSize: String) -> String? {
        let modelFileName = "ggml-\(modelSize).bin"

        let candidates = [
            "\(Config.configDir.path)/models/\(modelFileName)",
            "\(Config.legacyConfigDir.path)/models/\(modelFileName)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/whisper/\(modelFileName)",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }
}

/// Drains both process pipes concurrently so neither full pipe can stall the child.
enum ProcessOutput {
    static func read(stdout: Pipe, stderr: Pipe) -> (Data, Data) {
        let group = DispatchGroup()
        let stderrResult = LockedData()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrResult.store(stderr.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        return (stdoutData, stderrResult.value)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }
}

enum TranscriberError: LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let size):
            return "Speech model '\(size)' not found. Download it with: local-echo download-model \(size)"
        }
    }
}
