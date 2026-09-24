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
}
