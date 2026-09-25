import Darwin
import Foundation

/// Installs the Python MLX runtime and keeps each loaded model alive for 15 idle minutes.
/// Each model has its own lock, so loading or running one model never waits for another.
public final class ModelRuntime: @unchecked Sendable {
    public static let shared = ModelRuntime()
    public static let idleTimeout: TimeInterval = 15 * 60

    /// `lock` serializes loading and requests for one model. `session` and `generation` are guarded by the runtime lock.
    private final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var session: ModelSession?
        var generation = 0
    }

    private let lock = NSLock()
    private var slots: [String: Slot] = [:]
    /// Incremented by `stopAll`, so a session that finishes loading afterwards is discarded.
    private var epoch = 0

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

    /// Starts an installed model in the background so the next request does not wait for it to load.
    public func warmUp(_ model: ModelCatalog.Model) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard model.isInstalled else { return }
            let slot = self.slot(for: model.id)
            slot.lock.lock()
            defer { slot.lock.unlock() }
            do {
                _ = try self.runningSession(for: model, in: slot)
                self.scheduleExpiry(of: slot)
            } catch {
                fputs("Could not preload \(model.id): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Stops every model process without waiting for requests in progress; those requests fail.
    public func stopAll() {
        lock.lock()
        epoch += 1
        let sessions = slots.values.compactMap(\.session)
        for slot in slots.values {
            slot.session = nil
            slot.generation += 1
        }
        lock.unlock()
        for session in sessions { session.terminate() }
    }

    private func use(model: ModelCatalog.Model, request: [String: String], prompt: String?) throws -> String {
        let slot = slot(for: model.id)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        let session = try runningSession(for: model, in: slot)
        do {
            let result = try session.request(request, prompt: prompt)
            scheduleExpiry(of: slot)
            return result
        } catch {
            discard(session, from: slot)
            throw error
        }
    }

    private func slot(for modelID: String) -> Slot {
        lock.lock()
        defer { lock.unlock() }
        if let slot = slots[modelID] { return slot }
        let slot = Slot()
        slots[modelID] = slot
        return slot
    }

    /// Returns the model's running session, starting one if needed. Call with `slot.lock` held.
    private func runningSession(for model: ModelCatalog.Model, in slot: Slot) throws -> ModelSession {
        lock.lock()
        let current = slot.session
        let startEpoch = epoch
        lock.unlock()
        if let current {
            if current.isRunning { return current }
            discard(current, from: slot)
        }

        let session = try ModelSession(model: model)
        lock.lock()
        let stopped = epoch != startEpoch
        if !stopped { slot.session = session }
        lock.unlock()
        if stopped {
            session.stop()
            throw ModelRuntimeError.workerFailed("Model runtime stopped")
        }
        return session
    }

    private func discard(_ session: ModelSession, from slot: Slot) {
        lock.lock()
        if slot.session === session { slot.session = nil }
        lock.unlock()
        session.stop()
    }

    private func scheduleExpiry(of slot: Slot) {
        lock.lock()
        slot.generation += 1
        let generation = slot.generation
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            self?.expire(slot, generation: generation)
        }
    }

    private func expire(_ slot: Slot, generation: Int) {
        // Waits for a request in progress; that request makes this expiry stale.
        slot.lock.lock()
        defer { slot.lock.unlock() }
        lock.lock()
        guard slot.generation == generation, let session = slot.session else {
            lock.unlock()
            return
        }
        slot.session = nil
        lock.unlock()
        session.stop()
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
