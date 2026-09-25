import XCTest
@testable import LocalEchoLib

final class WhisperMarkersTests: XCTestCase {
    func testBlankAudioMarker() {
        XCTAssertEqual(WhisperMarkers.strip("[BLANK_AUDIO]"), "")
    }

    func testBlankAudioWithWhitespace() {
        XCTAssertEqual(WhisperMarkers.strip("  [BLANK_AUDIO]  "), "")
    }

    func testMultipleMarkers() {
        XCTAssertEqual(WhisperMarkers.strip("[BLANK_AUDIO] [silence]"), "")
    }

    func testParenthesizedMarker() {
        XCTAssertEqual(WhisperMarkers.strip("(BLANK_AUDIO)"), "")
    }

    func testNonSpeechEventMarkers() {
        XCTAssertEqual(WhisperMarkers.strip("[Music] [Applause]"), "")
    }

    func testMarkerMixedWithText() {
        XCTAssertEqual(WhisperMarkers.strip("hello [BLANK_AUDIO] world"), "hello world")
    }

    func testMarkerAtStartOfText() {
        XCTAssertEqual(WhisperMarkers.strip("[BLANK_AUDIO] hello"), "hello")
    }

    func testMarkerAtEndOfText() {
        XCTAssertEqual(WhisperMarkers.strip("hello [BLANK_AUDIO]"), "hello")
    }

    func testNormalTextUnchanged() {
        XCTAssertEqual(WhisperMarkers.strip("hello world"), "hello world")
    }

    func testEmptyString() {
        XCTAssertEqual(WhisperMarkers.strip(""), "")
    }

    func testUnknownBracketsPreserved() {
        XCTAssertEqual(WhisperMarkers.strip("see [1] and (later)"), "see [1] and (later)")
    }

    func testKnownMarkerStrippedUnknownPreserved() {
        XCTAssertEqual(WhisperMarkers.strip("[BLANK_AUDIO] see [1]"), "see [1]")
    }
}
