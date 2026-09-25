import Foundation

// Configuration is set before the URLSession task starts; delegate callbacks use its serial queue.
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    private static let downloadLock = NSLock()

    private var onProgress: ((Double) -> Void)?
    private var completion: ((Error?) -> Void)?
    private var destPath: URL?

    public static func download(_ model: ModelCatalog.Model, onProgress: ((Double) -> Void)? = nil) throws {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        if model.backend != .whisper {
            if model.isInstalled { return }
            guard let repository = model.repository else { throw ModelDownloadError.downloadFailed }
            let process = Process()
            process.executableURL = try PythonRuntime.pythonURL()
            process.arguments = [PythonRuntime.workerURL().path, "prepare", repository, model.directory.path]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let (_, errors) = ProcessOutput.read(stdout: stdout, stderr: stderr)
            process.waitUntilExit()
            guard process.terminationStatus == 0, model.isInstalled else {
                let detail = String(data: errors, encoding: .utf8) ?? "Unknown download error"
                throw ModelDownloadError.runtimeError(detail.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            onProgress?(100)
            return
        }
        let destPath = model.whisperDownloadURL
        let modelsDir = destPath.deletingLastPathComponent()

        if let existing = model.whisperFileURL {
            print("Model '\(model.id)' already exists at \(existing.path)")
            return
        }

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let urlString = "\(baseURL)/\(destPath.lastPathComponent)"
        guard let url = URL(string: urlString) else {
            throw ModelDownloadError.downloadFailed
        }

        print("Downloading \(model.id) model from \(urlString)...")

        let downloader = ModelDownloader()
        downloader.onProgress = onProgress
        downloader.destPath = destPath

        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        downloader.completion = { error in
            downloadError = error
            semaphore.signal()
        }

        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()

        semaphore.wait()
        session.invalidateAndCancel()

        if let error = downloadError {
            throw error
        }

        print("Model downloaded to \(destPath.path)")
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destPath = destPath else {
            completion?(ModelDownloadError.downloadFailed)
            return
        }
        do {
            if let httpResponse = downloadTask.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion?(ModelDownloadError.httpError(httpResponse.statusCode))
                return
            }

            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }
            try FileManager.default.moveItem(at: location, to: destPath)

            if !ModelDownloader.isValidGGMLFile(at: destPath) {
                try? FileManager.default.removeItem(at: destPath)
                completion?(ModelDownloadError.invalidModelData)
                return
            }

            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    public static func isValidGGMLFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        guard let magic = try? handle.read(upToCount: 4), magic.count == 4 else { return false }
        // GGML magic: 0x67676d6c ("ggml"), GGJT magic: 0x67676a74 ("ggjt"), GGUF magic: 0x46554747 ("GGUF")
        let magicU32 = magic.withUnsafeBytes { $0.load(as: UInt32.self) }
        let knownMagics: Set<UInt32> = [0x67676d6c, 0x67676a74, 0x46554747]
        return knownMagics.contains(magicU32)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100.0
        onProgress?(percent)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion?(error)
        }
    }
}

public enum ModelDownloadError: LocalizedError {
    case downloadFailed
    case httpError(Int)
    case invalidModelData
    case runtimeError(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download model"
        case .httpError(let statusCode):
            return "Download failed with HTTP status \(statusCode). Check your network connection or proxy settings."
        case .invalidModelData:
            return "Downloaded file is not a valid GGML model (possibly a proxy error page). Check your network connection or try downloading from a different network."
        case .runtimeError(let detail):
            return "Model setup failed: \(detail)"
        }
    }
}
