import XCTest
@testable import LocalEchoLib

final class TranscriptionJobTests: XCTestCase {
    func testBlankWhisperPromptIsNotSent() {
        var config = Config.defaultConfig
        config.whisperPrompt = "   "
        XCTAssertNil(TranscriptionJob(config: config).whisperPrompt)
        config.whisperPrompt = "Vocabulaire : Local-Echo"
        XCTAssertEqual(TranscriptionJob(config: config).whisperPrompt, "Vocabulaire : Local-Echo")
    }

    func testCleanupIsSkippedWhenOffOrWithoutEdits() {
        var config = Config.defaultConfig
        XCTAssertEqual(TranscriptionJob(config: config).cleanup, .defaults)

        config.cleanupOptions = CleanupOptions(formattingLevel: .none, correctRecognitionErrors: false, removeFillers: false)
        XCTAssertNil(TranscriptionJob(config: config).cleanup)

        config.cleanupOptions = .defaults
        config.cleanupModel = nil
        XCTAssertNil(TranscriptionJob(config: config).cleanup)
    }

    func testJobKeepsTheModelChosenWhenItStarted() {
        var config = Config.defaultConfig
        config.modelSize = "parakeet-tdt-v3-mixed"
        let job = TranscriptionJob(config: config)
        config.modelSize = "large-v3-turbo"
        XCTAssertEqual(job.modelID, "parakeet-tdt-v3-mixed")
    }
}
