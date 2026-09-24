import Darwin
import Foundation

/// Installs the Python MLX runtime and keeps each loaded model alive for 15 idle minutes.
public final class ModelRuntime: @unchecked Sendable {
    public static let shared = ModelRuntime()
    public static let idleTimeout: TimeInterval = 15 * 60

    private let lock = NSRecursiveLock()
    private var sessions: [String: ModelSession] = [:]
    private var generations: [String: Int] = [:]

    private init() {}

    public func transcribe(model: ModelCatalog.Model, audioURL: URL, prompt: String? = nil) throws -> String {
        try use(model: model, request: ["audio": audioURL.path], prompt: prompt)
    }

    public func clean(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return try use(model: ModelCatalog.cleanup, request: ["text": text], prompt: nil)
    }

    private func use(model: ModelCatalog.Model, request: [String: String], prompt: String?) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let session: ModelSession
        if let current = sessions[model.id], current.isRunning {
            session = current
        } else {
            session = try ModelSession(model: model)
            sessions[model.id] = session
        }
        do {
            let result = try session.request(request, prompt: prompt)
            let generation = (generations[model.id] ?? 0) + 1
            generations[model.id] = generation
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
                self?.expire(modelID: model.id, generation: generation)
            }
            return result
        } catch {
            session.stop()
            sessions.removeValue(forKey: model.id)
            throw error
        }
    }

    private func expire(modelID: String, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generations[modelID] == generation else { return }
        sessions.removeValue(forKey: modelID)?.stop()
    }

    public func stopAll() {
        lock.lock()
        defer { lock.unlock() }
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        generations.removeAll()
    }
}

/// A persistent process for one model. Whisper uses its loopback server; MLX uses JSON lines.
private final class ModelSession {
    let process = Process()
    private var input: Pipe?
    private var output: Pipe?
    private var port: UInt16?
    var isRunning: Bool { process.isRunning }

    init(model: ModelCatalog.Model) throws {
        switch model.backend {
        case .whisper:
            guard let binary = Transcriber.findWhisperServerBinary(),
                  let path = Transcriber.findModel(modelSize: model.id) else {
                throw ModelRuntimeError.missingModel(model.id)
            }
            let port = try Self.availablePort()
            self.port = port
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["--model", path, "--host", "127.0.0.1", "--port", String(port),
                                 "--language", "auto", "--no-timestamps", "--max-context", "0"]
            process.standardOutput = FileHandle.standardError
            process.standardError = FileHandle.standardError
            try process.run()
            try waitForServer(port: port)
        case .qwenASR, .parakeet, .cleanup:
            guard ModelDownloader.modelExists(model.id) else { throw ModelRuntimeError.missingModel(model.id) }
            let stdin = Pipe()
            let stdout = Pipe()
            input = stdin
            output = stdout
            process.executableURL = try PythonRuntime.pythonURL()
            process.arguments = [PythonRuntime.workerURL().path, "serve", model.backend.rawValue, model.directory.path]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.standardError
            try process.run()
            let ready: [String: Any]
            do {
                ready = try readMessage()
            } catch {
                stop()
                throw error
            }
            guard ready["ready"] as? Bool == true else { throw ModelRuntimeError.workerFailed("Model did not become ready") }
        }
    }

    func request(_ values: [String: String], prompt: String?) throws -> String {
        if let port {
            return try whisperRequest(port: port, audioPath: values["audio"] ?? "", prompt: prompt)
        }
        guard let input, process.isRunning else { throw ModelRuntimeError.workerFailed("Model worker stopped") }
        let data = try JSONSerialization.data(withJSONObject: values)
        input.fileHandleForWriting.write(data + Data([0x0a]))
        let response = try readMessage()
        if let error = response["error"] as? String { throw ModelRuntimeError.workerFailed(error) }
        guard let text = response["text"] as? String else { throw ModelRuntimeError.workerFailed("Invalid model response") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        input?.fileHandleForWriting.closeFile()
        output?.fileHandleForReading.closeFile()
    }

    private func readMessage() throws -> [String: Any] {
        guard let handle = output?.fileHandleForReading else { throw ModelRuntimeError.workerFailed("No model response") }
        var data = Data()
        while true {
            guard let byte = try handle.read(upToCount: 1), !byte.isEmpty else {
                throw ModelRuntimeError.workerFailed("Model worker exited")
            }
            if byte[0] == 0x0a { break }
            data.append(byte)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelRuntimeError.workerFailed("Invalid model response")
        }
        return object
    }

    private func waitForServer(port: UInt16) throws {
        for _ in 0..<150 {
            if !process.isRunning { throw ModelRuntimeError.workerFailed("whisper-server exited") }
            if let url = URL(string: "http://127.0.0.1:\(port)/health"),
               let (_, status) = try? Self.http(URLRequest(url: url)), status == 200 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()
        throw ModelRuntimeError.workerFailed("whisper-server did not start")
    }

    private func whisperRequest(port: UInt16, audioPath: String, prompt: String?) throws -> String {
        let boundary = "LocalEcho\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("response_format", "text")
        field("language", "auto")
        field("no_timestamps", "true")
        field("max_context", "0")
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: URL(fileURLWithPath: audioPath)))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        let (data, status) = try Self.http(request)
        guard status == 200, let text = String(data: data, encoding: .utf8) else {
            throw ModelRuntimeError.workerFailed("Whisper server returned HTTP \(status)")
        }
        return Transcriber.stripWhisperMarkers(text)
    }

    private static func http(_ request: URLRequest) throws -> (Data, Int) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedHTTPResult()
        URLSession.shared.dataTask(with: request) { data, response, error in
            result.store(data: data, status: (response as? HTTPURLResponse)?.statusCode, error: error)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.value()
    }

    private static func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ModelRuntimeError.workerFailed("Could not allocate loopback port") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: in_addr_t(0x0100007f))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw ModelRuntimeError.workerFailed("Could not bind loopback port") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw ModelRuntimeError.workerFailed("Could not read loopback port") }
        return UInt16(bigEndian: address.sin_port)
    }
}

private final class LockedHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var status: Int?
    private var error: Error?
    func store(data: Data?, status: Int?, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        self.data = data; self.status = status; self.error = error
    }
    func value() throws -> (Data, Int) {
        lock.lock(); defer { lock.unlock() }
        if let error { throw error }
        guard let data, let status else { throw ModelRuntimeError.workerFailed("No HTTP response") }
        return (data, status)
    }
}

public enum ModelRuntimeError: LocalizedError {
    case missingModel(String)
    case workerFailed(String)
    public var errorDescription: String? {
        switch self {
        case .missingModel(let id): return "Model \(id) is not downloaded"
        case .workerFailed(let reason): return reason
        }
    }
}
