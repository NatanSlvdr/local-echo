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

    public func clean(_ text: String, options: CleanupOptions) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        var request = options.requestFields
        request["text"] = text
        return try use(model: ModelCatalog.cleanup, request: request, prompt: nil)
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
