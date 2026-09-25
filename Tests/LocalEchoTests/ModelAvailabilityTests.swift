import XCTest
@testable import LocalEchoLib

final class ModelAvailabilityTests: XCTestCase {
    func testCatalogHasUniqueIDsAndRepositories() {
        let models = ModelCatalog.speech + [ModelCatalog.cleanup]
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models where model.backend != .whisper {
            XCTAssertNotNil(model.repository)
        }
    }

    func testAllSpeechModelsHaveOneSizeCategory() {
        XCTAssertEqual(ModelCatalog.speech.count, 4)
        XCTAssertEqual(ModelCatalog.speech.filter { $0.sizeCategory == .lightweight }.map(\.id),
                       ["parakeet-tdt-v3-mixed"])
        XCTAssertEqual(ModelCatalog.speech.filter { $0.sizeCategory == .medium }.map(\.id),
                       ["qwen3-asr-1.7b-4bit"])
        XCTAssertEqual(Set(ModelCatalog.speech.filter { $0.sizeCategory == .heavy }.map(\.id)),
                       Set(["qwen3-asr-1.7b-8bit", "large-v3-turbo"]))
    }

    func testSpeechModelsAreOrderedFromLightestToHeaviest() {
        XCTAssertEqual(ModelCatalog.speechByWeight.map(\.id),
                       ["parakeet-tdt-v3-mixed", "qwen3-asr-1.7b-4bit", "qwen3-asr-1.7b-8bit", "large-v3-turbo"])
    }

    func testMixedPrecisionQwenUsesItsOwnWorkerBackend() {
        XCTAssertEqual(ModelCatalog.speechModel("qwen3-asr-1.7b-4bit")?.backend, .qwenASRSession)
        XCTAssertEqual(ModelCatalog.speechModel("qwen3-asr-1.7b-8bit")?.backend, .qwenASR)
    }

    func testEverySpeechModelHasASummary() {
        for model in ModelCatalog.speech {
            XCTAssertFalse(model.summary.isEmpty, model.id)
        }
    }
}
