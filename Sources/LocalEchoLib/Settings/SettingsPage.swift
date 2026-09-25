import SwiftUI

enum SettingsPage: String, Hashable, CaseIterable {
    case general, transcription, cleanup, audio, controls, advanced, about

    var title: String {
        switch self {
        case .general: "Général"
        case .transcription: "Transcription"
        case .cleanup: "Nettoyage du texte"
        case .audio: "Audio"
        case .controls: "Raccourci"
        case .advanced: "Avancé"
        case .about: "À propos"
        }
    }

    /// One sentence at the top of the page that says what the page is for.
    var summary: String {
        switch self {
        case .general: "Dictée vocale locale pour macOS."
        case .transcription: "Le modèle qui transforme votre voix en texte. Il fonctionne entièrement sur ce Mac, même hors ligne."
        case .cleanup: "Un petit modèle local relit chaque transcription pour en corriger la forme, sans changer ce que vous avez dit."
        case .audio: "Le micro utilisé pour la dictée, et ce que fait votre Mac pendant que vous parlez."
        case .controls: "La touche qui lance la dictée, dans n'importe quelle app."
        case .advanced: "Le fichier de configuration pour les options absentes de cette fenêtre, et le retour aux réglages d'origine."
        case .about: "Dictée vocale locale pour macOS."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .transcription: "waveform"
        case .cleanup: "wand.and.stars"
        case .audio: "mic.fill"
        case .controls: "keyboard.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .transcription: .blue
        case .cleanup: .purple
        case .audio: .orange
        case .controls: .red
        case .advanced: .indigo
        case .about: .teal
        }
    }

    var searchTerms: String {
        switch self {
        case .general: "vue d'ensemble dicter essayer tester comment autorisations accessibilité microphone permission"
        case .transcription: "modèle reconnaissance vocale taille téléchargement langue"
        case .cleanup: "nettoyage correction texte modèle mise en forme ponctuation majuscules paragraphes liste hésitations"
        case .audio: "microphone entrée son volume baisser enregistrements conserver"
        case .controls: "enregistrement raccourci clavier touches combinaison maintenir appuyer fn globe"
        case .advanced: "configuration fichier ouvrir recharger réinitialiser défaut"
        case .about: "version licence compatibilité code source confidentialité"
        }
    }
}
