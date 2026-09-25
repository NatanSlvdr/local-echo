import AppKit
import Foundation

public struct Config: Codable, Sendable {
    public var hotkeys: [HotkeyConfig]
    public var modelSize: String
    public var cleanupModel: String?
    public var cleanupOptions: CleanupOptions
    public var whisperPrompt: String?
    public var maxRecordings: Int?
    public var toggleMode: FlexBool?
    // The former duckOtherAudio key is ignored so affected installs restart with ducking off.
    public var duckOtherAudioDuringRecording: FlexBool?
    public var audioInputDeviceID: UInt32?
    public var audioInputDeviceUID: String?

    public var usesToggleMode: Bool {
        get { toggleMode?.value ?? false }
        set { toggleMode = FlexBool(newValue) }
    }

    public var duckOtherAudioEnabled: Bool {
        get { duckOtherAudioDuringRecording?.value ?? false }
        set { duckOtherAudioDuringRecording = FlexBool(newValue) }
    }

    public var hotkey: HotkeyConfig {
        get { hotkeys[0] }
        set { hotkeys = Config.deduplicateHotkeys([newValue]) }
    }

    public func hotkeySummary() -> String {
        hotkeys
            .map { KeyCodes.describe(keyCode: $0.keyCode, modifiers: $0.modifiers) }
            .joined(separator: " · ")
    }

    public func hotkeyDisplaySummary() -> String {
        hotkeys
            .map { KeyCodes.displayName(keyCode: $0.keyCode, modifiers: $0.modifiers) }
            .joined(separator: " · ")
    }

    /// The shortcut and how it is used, as shown in the menu and Settings.
    var shortcutSummary: String {
        "\(hotkeyDisplaySummary()) · \(usesToggleMode ? "Appuyer" : "Maintenir")"
    }

    /// Whether cleanup runs and how much it formats, as shown in the menu and Settings.
    var cleanupSummary: String {
        cleanupModel == nil ? "Désactivé" : "Mise en forme \(cleanupOptions.formattingLevel.title.lowercased())"
    }

    /// The configured microphone among connected devices, or nil for the system default.
    /// A stored UID wins over the numeric ID, which can change after a reboot.
    func selectedInputDevice(in devices: [AudioInputDevice]) -> AudioInputDevice? {
        if let uid = audioInputDeviceUID {
            return devices.first { $0.uid == uid }
        }
        if let id = audioInputDeviceID {
            return devices.first { $0.id == id }
        }
        return nil
    }

    private static func deduplicateHotkeys(_ list: [HotkeyConfig]) -> [HotkeyConfig] {
        var out: [HotkeyConfig] = []
        for h in list where !out.contains(h) {
            out.append(h)
        }
        return out
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey
        case hotkeys
        case modelSize
        case cleanupModel
        case cleanupOptions
        case whisperPrompt
        case maxRecordings
        case toggleMode
        case duckOtherAudioDuringRecording
        case audioInputDeviceID
        case audioInputDeviceUID
    }

    /// Keys written by older versions. A file containing one is saved again without it.
    static let removedKeys = ["language", "spokenPunctuation", "modelPath"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hotkeysList = try c.decodeIfPresent([HotkeyConfig].self, forKey: .hotkeys)
        let legacyHotkey = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey)
        if let list = hotkeysList, !list.isEmpty {
            self.hotkeys = Config.deduplicateHotkeys(list)
        } else if let legacy = legacyHotkey {
            self.hotkeys = [legacy]
        } else {
            self.hotkeys = [HotkeyConfig(keyCode: 63, modifiers: [])]
        }
        self.modelSize = try c.decode(String.self, forKey: .modelSize)
        self.cleanupModel = try c.decodeIfPresent(String.self, forKey: .cleanupModel) ?? ModelCatalog.cleanup.id
        if cleanupModel == "off" { cleanupModel = nil }
        if cleanupModel != nil && cleanupModel != ModelCatalog.cleanup.id { cleanupModel = ModelCatalog.cleanup.id }
        self.cleanupOptions = try c.decodeIfPresent(CleanupOptions.self, forKey: .cleanupOptions) ?? .defaults
        self.whisperPrompt = try c.decodeIfPresent(String.self, forKey: .whisperPrompt)
        self.maxRecordings = try c.decodeIfPresent(Int.self, forKey: .maxRecordings)
        self.toggleMode = try c.decodeIfPresent(FlexBool.self, forKey: .toggleMode)
        self.duckOtherAudioDuringRecording = try c.decodeIfPresent(FlexBool.self, forKey: .duckOtherAudioDuringRecording)
        self.audioInputDeviceID = try c.decodeIfPresent(UInt32.self, forKey: .audioInputDeviceID)
        self.audioInputDeviceUID = try c.decodeIfPresent(String.self, forKey: .audioInputDeviceUID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hotkeys, forKey: .hotkeys)
        try c.encode(hotkeys[0], forKey: .hotkey)
        try c.encode(modelSize, forKey: .modelSize)
        try c.encode(cleanupModel ?? "off", forKey: .cleanupModel)
        try c.encode(cleanupOptions, forKey: .cleanupOptions)
        try c.encodeIfPresent(whisperPrompt, forKey: .whisperPrompt)
        try c.encodeIfPresent(maxRecordings, forKey: .maxRecordings)
        try c.encodeIfPresent(toggleMode, forKey: .toggleMode)
        try c.encodeIfPresent(duckOtherAudioDuringRecording, forKey: .duckOtherAudioDuringRecording)
        try c.encodeIfPresent(audioInputDeviceID, forKey: .audioInputDeviceID)
        try c.encodeIfPresent(audioInputDeviceUID, forKey: .audioInputDeviceUID)
    }

    public init(
        hotkeys: [HotkeyConfig],
        modelSize: String,
        cleanupModel: String? = ModelCatalog.cleanup.id,
        cleanupOptions: CleanupOptions = .defaults,
        whisperPrompt: String? = nil,
        maxRecordings: Int?,
        toggleMode: FlexBool?,
        duckOtherAudioDuringRecording: FlexBool? = nil,
        audioInputDeviceID: UInt32? = nil,
        audioInputDeviceUID: String? = nil
    ) {
        self.hotkeys = hotkeys.isEmpty
            ? [HotkeyConfig(keyCode: 63, modifiers: [])]
            : Config.deduplicateHotkeys(hotkeys)
        self.modelSize = modelSize
        self.cleanupModel = cleanupModel
        self.cleanupOptions = cleanupOptions
        self.whisperPrompt = whisperPrompt
        self.maxRecordings = maxRecordings
        self.toggleMode = toggleMode
        self.duckOtherAudioDuringRecording = duckOtherAudioDuringRecording
        self.audioInputDeviceID = audioInputDeviceID
        self.audioInputDeviceUID = audioInputDeviceUID
    }

    public static let supportedModels = ModelCatalog.speech.map(\.id)

    // Removed model selections migrate to the existing multilingual default.
    public static func supportedModel(_ size: String) -> String {
        return supportedModels.contains(size) ? size : defaultConfig.modelSize
    }

    public static let defaultMaxRecordings = 0

    public static func effectiveMaxRecordings(_ value: Int?) -> Int {
        let raw = value ?? Config.defaultMaxRecordings
        if raw == 0 { return 0 }
        return min(max(1, raw), 100)
    }

    public static let defaultConfig = Config(
        hotkeys: [HotkeyConfig(keyCode: 63, modifiers: [])],
        modelSize: "large-v3-turbo",
        whisperPrompt: nil,
        maxRecordings: nil,
        toggleMode: FlexBool(false),
        duckOtherAudioDuringRecording: FlexBool(false)
    )

    public static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/local-echo")
    }

    // Keep settings from installations made before the app was renamed.
    static var legacyConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/open-wispr")
    }

    public static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    public static func load() -> Config {
        let source = FileManager.default.fileExists(atPath: configFile.path)
            ? configFile
            : legacyConfigDir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: source) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }

        do {
            var config = try JSONDecoder().decode(Config.self, from: data)
            let resolved = Config.supportedModel(config.modelSize)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let hasRemovedKeys = removedKeys.contains { object?[$0] != nil }
            if resolved != config.modelSize || source != configFile || hasRemovedKeys {
                config.modelSize = resolved
                try? config.save()
            }
            return config
        } catch {
            fputs("Warning: unable to parse \(source.path): \(error.localizedDescription)\n", stderr)
            return Config.defaultConfig
        }
    }

    public static func decode(from data: Data) throws -> Config {
        var config = try JSONDecoder().decode(Config.self, from: data)
        config.modelSize = Config.supportedModel(config.modelSize)
        return config
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile, options: .atomic)
    }
}

public struct FlexBool: Codable, Sendable {
    public let value: Bool

    public init(_ value: Bool) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            value = b
        } else if let s = try? container.decode(String.self) {
            value = ["true", "yes", "1"].contains(s.lowercased())
        } else if let i = try? container.decode(Int.self) {
            value = i != 0
        } else {
            value = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct HotkeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: [String]

    public init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: UInt64 {
        let flags = modifiers.compactMap(Self.flag(forModifier:))
        return UInt64(NSEvent.ModifierFlags(flags).rawValue)
    }

    /// The flag for a modifier name stored in the configuration, including accepted aliases.
    static func flag(forModifier name: String) -> NSEvent.ModifierFlags? {
        switch name.lowercased() {
        case "cmd", "command": .command
        case "shift": .shift
        case "ctrl", "control": .control
        case "opt", "option", "alt": .option
        case "fn", "globe": .function
        default: nil
        }
    }

    /// The configuration names of the held modifiers, in the order the settings window records them.
    static func modifierNames(in flags: NSEvent.ModifierFlags) -> [String] {
        let names: [(String, NSEvent.ModifierFlags)] = [
            ("cmd", .command), ("shift", .shift), ("opt", .option), ("ctrl", .control), ("fn", .function),
        ]
        return names.filter { flags.contains($0.1) }.map(\.0)
    }

    /// The flag a modifier key sets by itself, or nil when the key is not a modifier.
    static func modifierFlag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        case 63: .function
        default: nil
        }
    }
}
