import Foundation

/// How much the cleanup model may change the transcript's presentation.
public enum CleanupFormattingLevel: String, Codable, Sendable, CaseIterable {
    case none, light, polished, structured

    public var title: String {
        switch self {
        case .none: "Aucune"
        case .light: "Légère"
        case .polished: "Soignée"
        case .structured: "Structurée"
        }
    }

    public var explanation: String {
        switch self {
        case .none: "Conserve la présentation de la transcription. Les autres corrections activées restent possibles."
        case .light: "Ajuste la ponctuation, les majuscules et les espaces. Ex. « bonjour comment ça va » → « Bonjour, comment ça va ? »"
        case .polished: "Rend les phrases plus lisibles et sépare les sujets en paragraphes, sans listes. Ex. une nouvelle idée commence un nouveau paragraphe."
        case .structured: "Crée des paragraphes et, si vous énumérez clairement des points, une liste. Ex. « premièrement…, deuxièmement… » devient deux éléments. N'ajoute pas d'idées."
        }
    }
}

/// Independent text-cleanup choices with migration from the former formatting switches.
public struct CleanupOptions: Codable, Sendable, Equatable {
    public var formattingLevel: CleanupFormattingLevel
    public var correctRecognitionErrors: Bool
    public var removeFillers: Bool

    public static let defaults = CleanupOptions()

    public init(formattingLevel: CleanupFormattingLevel = .light,
                correctRecognitionErrors: Bool = true, removeFillers: Bool = false) {
        self.formattingLevel = formattingLevel
        self.correctRecognitionErrors = correctRecognitionErrors
        self.removeFillers = removeFillers
    }

    private enum CodingKeys: String, CodingKey {
        case formattingLevel, correctRecognitionErrors, removeFillers
        case formatText, addParagraphs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let level = try values.decodeIfPresent(CleanupFormattingLevel.self, forKey: .formattingLevel) {
            formattingLevel = level
        } else if try values.decodeIfPresent(Bool.self, forKey: .addParagraphs) == true {
            formattingLevel = .polished
        } else if try values.decodeIfPresent(Bool.self, forKey: .formatText) == false {
            formattingLevel = .none
        } else {
            formattingLevel = .light
        }
        correctRecognitionErrors = try values.decodeIfPresent(Bool.self, forKey: .correctRecognitionErrors) ?? true
        removeFillers = try values.decodeIfPresent(Bool.self, forKey: .removeFillers) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(formattingLevel, forKey: .formattingLevel)
        try values.encode(correctRecognitionErrors, forKey: .correctRecognitionErrors)
        try values.encode(removeFillers, forKey: .removeFillers)
    }

    public var hasEdits: Bool {
        formattingLevel != .none || correctRecognitionErrors || removeFillers
    }

    /// The worker protocol uses string fields alongside the transcript text.
    public var requestFields: [String: String] {
        [
            "formatting_level": formattingLevel.rawValue,
            "correct_recognition_errors": correctRecognitionErrors ? "true" : "false",
            "remove_fillers": removeFillers ? "true" : "false",
        ]
    }
}
