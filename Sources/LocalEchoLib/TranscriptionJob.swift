import Foundation

/// One transcription with the settings captured when it starts. A later config change affects only the next job.
struct TranscriptionJob: Sendable {
    let modelID: String
    let whisperPrompt: String?
    /// Nil when cleanup is off or every cleanup edit is disabled.
    let cleanup: CleanupOptions?

    init(config: Config) {
        modelID = config.modelSize
        let prompt = config.whisperPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        whisperPrompt = prompt.isEmpty ? nil : config.whisperPrompt
        cleanup = config.cleanupModel != nil && config.cleanupOptions.hasEdits ? config.cleanupOptions : nil
    }

    /// Starts the models this job needs, so loading overlaps the recording instead of following it.
    func warmUp() {
        guard let model = ModelCatalog.speechModel(modelID) else { return }
        ModelRuntime.shared.warmUp(model)
        if cleanup != nil { ModelRuntime.shared.warmUp(ModelCatalog.cleanup) }
    }

    /// Transcribes the audio, then applies cleanup when enabled. Cleanup failures keep the raw transcript.
    func run(audioURL: URL) throws -> String {
        guard let model = ModelCatalog.speechModel(modelID) else {
            throw TranscriptionError.modelNotFound(modelID)
        }
        let text = try ModelRuntime.shared.transcribe(model: model, audioURL: audioURL,
                                                      prompt: model.backend == .whisper ? whisperPrompt : nil)
        guard let cleanup, !text.isEmpty else { return text }
        do {
            return try ModelRuntime.shared.clean(text, options: cleanup)
        } catch {
            fputs("Cleanup unavailable: \(error.localizedDescription)\n", stderr)
            return text
        }
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let id):
            return "Speech model '\(id)' not found. Download it with: local-echo download-model \(id)"
        }
    }
}
