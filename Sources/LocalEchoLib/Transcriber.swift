import Foundation

public final class Transcriber: Sendable {
    private let modelSize: String
    private let whisperPrompt: String?
    public let spokenPunctuation: Bool

    public init(modelSize: String = "large-v3-turbo", whisperPrompt: String? = nil, spokenPunctuation: Bool = false) {
        self.modelSize = modelSize
        self.whisperPrompt = whisperPrompt
        self.spokenPunctuation = spokenPunctuation
    }

    public func transcribe(audioURL: URL) throws -> String {
        guard let whisperPath = Transcriber.findWhisperBinary() else {
            throw TranscriberError.whisperNotFound
        }

        guard let modelPath = Transcriber.findModel(modelSize: modelSize) else {
            throw TranscriberError.modelNotFound(modelSize)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = arguments(modelPath: modelPath, audioURL: audioURL)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let (data, stderrData) = ProcessOutput.read(stdout: stdoutPipe, stderr: stderrPipe)
        process.waitUntilExit()

        let output = Transcriber.stripWhisperMarkers(
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderr.isEmpty { fputs("whisper-cli: \(stderr)\n", Foundation.stderr) }
            throw TranscriberError.transcriptionFailed
        }

        return output
    }

    func arguments(modelPath: String, audioURL: URL) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", "auto",
            "-nt",
            // Disable cross-window context carry-over. whisper.cpp feeds each
            // 30s window's decoded text as the prompt for the next window; on
            // long dictation this compounds into repetition/hallucination
            // loops (sentences repeating verbatim, then trailing off).
            // max-context 0 decodes each window independently and stops it.
            "-mc", "0",
        ]
        if let prompt = effectiveWhisperPrompt {
            args += ["--prompt", prompt]
        }
        if spokenPunctuation {
            args += ["--suppress-regex", "[,\\.\\?!;:\\-—]"]
        }

        return args
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
        return findModel(modelSize: modelSize) != nil
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
    case whisperNotFound
    case modelNotFound(String)
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cli not found. Rebuild Local-Echo.app with whisper-cli on PATH."
        case .modelNotFound(let size):
            return "Whisper model '\(size)' not found. Download it with: local-echo download-model \(size)"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
