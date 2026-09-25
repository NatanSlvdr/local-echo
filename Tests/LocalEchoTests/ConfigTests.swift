import XCTest
@testable import LocalEchoLib

final class ConfigTests: XCTestCase {

    // MARK: - effectiveMaxRecordings

    func testEffectiveMaxRecordingsNilDefaultsToZero() {
        XCTAssertEqual(Config.effectiveMaxRecordings(nil), 0)
    }

    func testEffectiveMaxRecordingsZero() {
        XCTAssertEqual(Config.effectiveMaxRecordings(0), 0)
    }

    func testEffectiveMaxRecordingsNegativeClampsToOne() {
        XCTAssertEqual(Config.effectiveMaxRecordings(-5), 1)
    }

    func testEffectiveMaxRecordingsWithinRange() {
        XCTAssertEqual(Config.effectiveMaxRecordings(1), 1)
        XCTAssertEqual(Config.effectiveMaxRecordings(10), 10)
        XCTAssertEqual(Config.effectiveMaxRecordings(100), 100)
    }

    func testEffectiveMaxRecordingsClampsAbove100() {
        XCTAssertEqual(Config.effectiveMaxRecordings(200), 100)
        XCTAssertEqual(Config.effectiveMaxRecordings(999), 100)
    }

    // MARK: - FlexBool decoding

    func testFlexBoolDecodesBool() throws {
        let json = #"{"spokenPunctuation": true}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(FlexBoolWrapper.self, from: json)
        XCTAssertTrue(wrapper.spokenPunctuation.value)
    }

    func testFlexBoolDecodesStringTrue() throws {
        let json = #"{"spokenPunctuation": "yes"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(FlexBoolWrapper.self, from: json)
        XCTAssertTrue(wrapper.spokenPunctuation.value)
    }

    func testFlexBoolDecodesStringFalse() throws {
        let json = #"{"spokenPunctuation": "no"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(FlexBoolWrapper.self, from: json)
        XCTAssertFalse(wrapper.spokenPunctuation.value)
    }

    func testFlexBoolDecodesInt() throws {
        let json1 = #"{"spokenPunctuation": 1}"#.data(using: .utf8)!
        let wrapper1 = try JSONDecoder().decode(FlexBoolWrapper.self, from: json1)
        XCTAssertTrue(wrapper1.spokenPunctuation.value)

        let json0 = #"{"spokenPunctuation": 0}"#.data(using: .utf8)!
        let wrapper0 = try JSONDecoder().decode(FlexBoolWrapper.self, from: json0)
        XCTAssertFalse(wrapper0.spokenPunctuation.value)
    }

    // MARK: - Config JSON decoding

    func testConfigDecodesWithMaxRecordings() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "spokenPunctuation": false,
            "maxRecordings": 5
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.maxRecordings, 5)
        XCTAssertEqual(config.modelSize, "large-v3-turbo")
    }

    func testConfigDecodesWithoutMaxRecordings() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "small.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertNil(config.maxRecordings)
        XCTAssertEqual(Config.effectiveMaxRecordings(config.maxRecordings), 0)
    }

    func testConfigDecodesWhisperPrompt() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base",
            "language": "auto",
            "whisperPrompt": "Use punctuation and capitalization."
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.whisperPrompt, "Use punctuation and capitalization.")
    }

    func testConfigEncodesWhisperPromptRoundTrip() throws {
        var config = Config.defaultConfig
        config.whisperPrompt = "Prefer concise sentences."
        let data = try JSONEncoder().encode(config)
        let decoded = try Config.decode(from: data)
        XCTAssertEqual(decoded.whisperPrompt, "Prefer concise sentences.")
    }

    func testConfigOmitsWhisperPromptWhenNil() throws {
        let data = try JSONEncoder().encode(Config.defaultConfig)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("whisperPrompt"))
    }

    // MARK: - toggleMode decoding

    func testConfigDecodesToggleModeTrue() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "toggleMode": true
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.toggleMode?.value, true)
    }

    func testConfigDecodesToggleModeFalse() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "toggleMode": false
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.toggleMode?.value, false)
    }

    func testConfigDecodesWithoutToggleMode() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertNil(config.toggleMode)
    }

    func testConfigDefaultToggleModeIsFalse() {
        let config = Config.defaultConfig
        XCTAssertEqual(config.toggleMode?.value, false)
    }

    func testAudioDuckingDefaultsToDisabledForExistingConfigs() throws {
        let json = #"{"modelSize":"base.en","language":"en","duckOtherAudio":true}"#.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertFalse(config.duckOtherAudioEnabled)
    }

    func testAudioDuckingSettingSurvivesConfigRoundTrip() throws {
        var config = Config.defaultConfig
        config.duckOtherAudioDuringRecording = FlexBool(true)
        let data = try JSONEncoder().encode(config)
        let decoded = try Config.decode(from: data)
        XCTAssertTrue(decoded.duckOtherAudioEnabled)
    }

    // MARK: - audioInputDevice decoding

    func testConfigDecodesAudioInputDeviceUID() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "audioInputDeviceID": 82,
            "audioInputDeviceUID": "AppleUSBAudioEngine:Vendor:Headset:1234:1"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.audioInputDeviceID, 82)
        XCTAssertEqual(config.audioInputDeviceUID, "AppleUSBAudioEngine:Vendor:Headset:1234:1")
    }

    func testConfigDecodesLegacyAudioInputDeviceIDWithoutUID() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "audioInputDeviceID": 82
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.audioInputDeviceID, 82)
        XCTAssertNil(config.audioInputDeviceUID)
    }

    func testConfigEncodesAudioInputDeviceUIDRoundTrip() throws {
        var config = Config.defaultConfig
        config.audioInputDeviceID = 82
        config.audioInputDeviceUID = "BuiltInMicrophoneDevice"
        let data = try JSONEncoder().encode(config)
        let decoded = try Config.decode(from: data)
        XCTAssertEqual(decoded.audioInputDeviceID, 82)
        XCTAssertEqual(decoded.audioInputDeviceUID, "BuiltInMicrophoneDevice")
    }

    func testConfigOmitsAudioInputDeviceUIDWhenNil() throws {
        let data = try JSONEncoder().encode(Config.defaultConfig)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("audioInputDeviceUID"))
    }

    // MARK: - Language and model constants

    func testFourSpeechModelsAreSelectable() {
        XCTAssertEqual(Config.supportedModels, ["qwen3-asr-1.7b-8bit", "parakeet-tdt-v3-mixed", "qwen3-asr-1.7b-4bit", "large-v3-turbo"])
    }

    func testSupportedModelsContainsDefault() {
        XCTAssertTrue(Config.supportedModels.contains(Config.defaultConfig.modelSize))
    }

    func testCleanupDefaultsOnAndCanBeDisabled() throws {
        let legacy = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo"}"#.utf8))
        XCTAssertEqual(legacy.cleanupModel, ModelCatalog.cleanup.id)
        let off = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo","cleanupModel":"off"}"#.utf8))
        XCTAssertNil(off.cleanupModel)
        let saved = String(data: try JSONEncoder().encode(off), encoding: .utf8)
        XCTAssertTrue(saved?.contains("\"cleanupModel\":\"off\"") == true)
    }

    func testCleanupOptionsMigrateAndRoundTrip() throws {
        let legacy = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo"}"#.utf8))
        XCTAssertEqual(legacy.cleanupOptions, .defaults)

        let partial = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo","cleanupOptions":{"removeFillers":true}}"#.utf8))
        XCTAssertEqual(partial.cleanupOptions.formattingLevel, .light)
        XCTAssertTrue(partial.cleanupOptions.correctRecognitionErrors)
        XCTAssertTrue(partial.cleanupOptions.removeFillers)

        var updated = partial
        updated.cleanupOptions.formattingLevel = .structured
        let restored = try Config.decode(from: JSONEncoder().encode(updated))
        XCTAssertEqual(restored.cleanupOptions, updated.cleanupOptions)
        XCTAssertEqual(restored.cleanupOptions.requestFields["formatting_level"], "structured")
    }

    func testCleanupOptionsMigrateOldSwitchesAndDiscardTerms() throws {
        let old = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo","cleanupOptions":{"formatText":false,"addParagraphs":false,"protectedTerms":"OpenAI"}}"#.utf8))
        XCTAssertEqual(old.cleanupOptions.formattingLevel, .none)
        let paragraphs = try Config.decode(from: Data(#"{"modelSize":"large-v3-turbo","cleanupOptions":{"formatText":true,"addParagraphs":true}}"#.utf8))
        XCTAssertEqual(paragraphs.cleanupOptions.formattingLevel, .polished)

        let saved = String(data: try JSONEncoder().encode(old), encoding: .utf8)!
        XCTAssertFalse(saved.contains("protectedTerms"))
        XCTAssertFalse(saved.contains("formatText"))
        XCTAssertFalse(saved.contains("addParagraphs"))
        XCTAssertTrue(saved.contains("\"formattingLevel\":\"none\""))
    }

    func testRemovedLargeModelMigratesToTurbo() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "large",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.modelSize, "large-v3-turbo")
    }

    func testLegacyLanguageIsIgnoredAndNotSaved() throws {
        let json = #"{"modelSize":"medium","language":"fr"}"#.data(using: .utf8)!
        let config = try Config.decode(from: json)
        let saved = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(object["language"])
        XCTAssertEqual(config.modelSize, "large-v3-turbo")
    }

    func testLegacyEnglishModelMovesToMultilingualDefault() throws {
        let json = #"{"modelSize":"base.en","language":"en"}"#.data(using: .utf8)!
        XCTAssertEqual(try Config.decode(from: json).modelSize, "large-v3-turbo")
    }

    // MARK: - HotkeyConfig modifier flags

    func testModifierFlagsSingle() {
        let config = HotkeyConfig(keyCode: 49, modifiers: ["cmd"])
        XCTAssertEqual(config.modifierFlags, UInt64(1 << 20))
    }

    func testModifierFlagsMultiple() {
        let config = HotkeyConfig(keyCode: 49, modifiers: ["cmd", "shift"])
        let expected = UInt64(1 << 20) | UInt64(1 << 17)
        XCTAssertEqual(config.modifierFlags, expected)
    }

    func testModifierFlagsEmpty() {
        let config = HotkeyConfig(keyCode: 63, modifiers: [])
        XCTAssertEqual(config.modifierFlags, 0)
    }

    func testModifierFlagsIgnoresUnknown() {
        let config = HotkeyConfig(keyCode: 49, modifiers: ["cmd", "bogus"])
        XCTAssertEqual(config.modifierFlags, UInt64(1 << 20))
    }

    // MARK: - Multiple hotkeys

    func testConfigDecodesHotkeysArray() throws {
        let json = """
        {
            "hotkeys": [
                {"keyCode": 63, "modifiers": []},
                {"keyCode": 96, "modifiers": []}
            ],
            "modelSize": "base.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.hotkeys.count, 2)
        XCTAssertEqual(config.hotkey.keyCode, 63)
        XCTAssertTrue(config.hotkeySummary().contains("·"))
    }

    func testConfigDeduplicatesIdenticalHotkeys() throws {
        let json = """
        {
            "hotkeys": [
                {"keyCode": 63, "modifiers": []},
                {"keyCode": 63, "modifiers": []}
            ],
            "modelSize": "base.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.hotkeys.count, 1)
    }

    func testConfigEncodeRoundtripPreservesHotkeys() throws {
        let json = """
        {
            "hotkeys": [
                {"keyCode": 63, "modifiers": []},
                {"keyCode": 96, "modifiers": []}
            ],
            "modelSize": "base.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        let data = try JSONEncoder().encode(config)
        let again = try Config.decode(from: data)
        XCTAssertEqual(again.hotkeys.count, 2)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["hotkey"])
        XCTAssertNotNil(obj?["hotkeys"])
    }
}

private struct FlexBoolWrapper: Codable {
    let spokenPunctuation: FlexBool
}
