import Foundation

/// The single catalog for model IDs, downloads, runtimes, and UI labels.
public enum ModelCatalog {
    public enum SizeCategory: String, CaseIterable, Sendable {
        case lightweight, medium, heavy
    }

    /// How a model is loaded. MLX backends are passed to worker.py by their raw value.
    public enum Backend: String, Sendable {
        case whisper
        /// Qwen3 ASR through mlx-audio.
        case qwenASR
        /// Qwen3 ASR through the mlx-qwen3-asr session API, which loads mixed-precision weights.
        case qwenASRSession
        case parakeet
        case cleanup
    }

    /// Accent colors for model icons; Settings maps them to system colors.
    public enum Tint: Sendable {
        case green, blue, purple, teal
    }

    public struct Model: Sendable {
        public let id: String
        public let name: String
        /// One sentence for the model choice in Settings.
        public let summary: String
        /// A one-word strength shown next to the name, if any.
        public let tag: String?
        public let symbol: String
        public let tint: Tint
        public let backend: Backend
        public let repository: String?
        public let approximateDownload: String
        public let sizeCategory: SizeCategory
    }

    public static let speech: [Model] = [
        Model(id: "qwen3-asr-1.7b-8bit", name: "Qwen3 ASR 1.7B INT8",
              summary: "La meilleure précision de Qwen3, au prix d'un modèle plus lourd.",
              tag: "Précis", symbol: "scope", tint: .purple, backend: .qwenASR,
              repository: "mlx-community/Qwen3-ASR-1.7B-8bit", approximateDownload: "~2,5 Go",
              sizeCategory: .heavy),
        Model(id: "parakeet-tdt-v3-mixed", name: "Parakeet TDT v3 Q4/Q8",
              summary: "Le plus rapide et le plus léger. 25 langues européennes, dont le français.",
              tag: "Rapide", symbol: "hare.fill", tint: .green, backend: .parakeet,
              repository: "MarkChen1214/parakeet-tdt-0.6b-v3-MLX-Mixed-4bit8bit", approximateDownload: "~400 Mo",
              sizeCategory: .lightweight),
        Model(id: "qwen3-asr-1.7b-4bit", name: "Qwen3 ASR 1.7B Q4/Q8",
              summary: "Bon équilibre entre précision, vitesse et taille.",
              tag: "Équilibré", symbol: "scalemass.fill", tint: .blue, backend: .qwenASRSession,
              repository: "moona3k/mlx-qwen3-asr-1.7b-4bit", approximateDownload: "~1,2 Go",
              sizeCategory: .medium),
        Model(id: "large-v3-turbo", name: "Whisper Large v3 Turbo",
              summary: "Polyvalent et éprouvé, reconnaît un très grand nombre de langues.",
              tag: "Multilingue", symbol: "globe", tint: .teal, backend: .whisper,
              repository: nil, approximateDownload: "~1,6 Go",
              sizeCategory: .heavy),
    ]

    public static let cleanup = Model(
        id: "qwen35-08b-qat-q4", name: "Qwen3.5 0.8B QAT Q4",
        summary: "Relit chaque transcription pour en corriger la forme.",
        tag: nil, symbol: "wand.and.stars", tint: .purple, backend: .cleanup,
        repository: "YoozLabs/Qwen3.5-0.8B-qat-lean-4bit-mlx", approximateDownload: "~500 Mo",
        sizeCategory: .lightweight
    )

    /// Speech models from lightest to heaviest, the order used by the menu and Settings.
    public static let speechByWeight: [Model] = SizeCategory.allCases.flatMap { category in
        speech.filter { $0.sizeCategory == category }
    }

    public static func speechModel(_ id: String) -> Model? { speech.first { $0.id == id } }
    public static func model(_ id: String) -> Model? { speechModel(id) ?? (id == cleanup.id ? cleanup : nil) }
    public static func isInstalled(_ id: String) -> Bool { model(id)?.isInstalled ?? false }
}

/// Where downloaded models live on disk.
extension ModelCatalog.Model {
    /// MLX models download into their own folder.
    public var directory: URL { Config.configDir.appendingPathComponent("models/\(id)") }

    /// The file a Whisper model downloads to.
    var whisperDownloadURL: URL { Config.configDir.appendingPathComponent("models/ggml-\(id).bin") }

    /// The installed Whisper file, including locations used by older versions and by whisper.cpp.
    var whisperFileURL: URL? {
        let fileName = "ggml-\(id).bin"
        let candidates = [
            whisperDownloadURL,
            Config.legacyConfigDir.appendingPathComponent("models/\(fileName)"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/whisper/\(fileName)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public var isInstalled: Bool {
        if backend == .whisper { return whisperFileURL != nil }
        guard let repository,
              let marker = try? String(contentsOf: directory.appendingPathComponent(".local-echo-ready"), encoding: .utf8),
              marker == repository else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .contains(where: { $0.hasSuffix(".safetensors") }) ?? false
    }
}
