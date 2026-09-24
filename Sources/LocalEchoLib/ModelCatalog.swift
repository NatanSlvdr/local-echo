import Foundation

/// The single catalog for model IDs, downloads, runtimes, and UI labels.
public enum ModelCatalog {
    public enum Backend: String, Sendable {
        case whisper, qwenASR, parakeet, cleanup
    }

    public struct Model: Sendable {
        public let id: String
        public let name: String
        public let backend: Backend
        public let repository: String?
        public let approximateDownload: String

        public var directory: URL { Config.configDir.appendingPathComponent("models/\(id)") }
    }

    public static let speech: [Model] = [
        Model(id: "qwen3-asr-1.7b-8bit", name: "Quality · Qwen3 ASR 1.7B INT8", backend: .qwenASR,
              repository: "mlx-community/Qwen3-ASR-1.7B-8bit", approximateDownload: "~2.5 GB"),
        Model(id: "parakeet-tdt-v3-mixed", name: "Compact · Parakeet TDT v3 Q4/Q8", backend: .parakeet,
              repository: "MarkChen1214/parakeet-tdt-0.6b-v3-MLX-Mixed-4bit8bit", approximateDownload: "~400 MB"),
        Model(id: "qwen3-asr-1.7b-4bit", name: "Balanced · Qwen3 ASR 1.7B Q4/Q8", backend: .qwenASR,
              repository: "moona3k/mlx-qwen3-asr-1.7b-4bit", approximateDownload: "~1.2 GB"),
        Model(id: "large-v3-turbo", name: "Whisper Large v3 Turbo", backend: .whisper,
              repository: nil, approximateDownload: "~1.6 GB"),
    ]

    public static let cleanup = Model(
        id: "qwen35-08b-qat-q4", name: "Qwen3.5 0.8B QAT Q4", backend: .cleanup,
        repository: "YoozLabs/Qwen3.5-0.8B-qat-lean-4bit-mlx", approximateDownload: "~500 MB"
    )

    public static func speechModel(_ id: String) -> Model? { speech.first { $0.id == id } }
    public static func model(_ id: String) -> Model? { speechModel(id) ?? (id == cleanup.id ? cleanup : nil) }
}
