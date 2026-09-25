import XCTest
@testable import LocalEchoLib

final class ModelAvailabilityTests: XCTestCase {
    func testCatalogHasUniqueIDsAndRepositories() {
        let models = ModelCatalog.speech + [ModelCatalog.cleanup]
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(Set(models.map(\.repository)).count, models.count)
    }

    func testEveryDownloadIsPinnedToACommit() {
        for model in ModelCatalog.speech + [ModelCatalog.cleanup] {
            XCTAssertEqual(model.revision.count, 40, model.id)
            XCTAssertTrue(model.revision.allSatisfy(\.isHexDigit), model.id)
            XCTAssertEqual(model.installMarker, "\(model.repository)@\(model.revision)")
        }
        let whisper = ModelCatalog.speechModel("large-v3-turbo")
        XCTAssertEqual(whisper?.fileSHA256?.count, 64)
        XCTAssertEqual(whisper?.whisperSourceURL?.absoluteString,
                       "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin")
    }

    func testSHA256OfFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try ModelDownloader.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
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
