import Foundation

public struct KeyCodes {
    public static let nameToCode: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "escape": 53,
        "rightcmd": 54, "cmd": 55, "leftcmd": 55,
        "shift": 56, "leftshift": 56,
        "capslock": 57,
        "option": 58, "leftoption": 58, "alt": 58, "leftalt": 58,
        "ctrl": 59, "leftctrl": 59, "control": 59,
        "rightshift": 60,
        "rightoption": 61, "rightalt": 61,
        "rightctrl": 62, "rightcontrol": 62,
        "fn": 63, "globe": 63,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113,
    ]

    public static let codeToName: [UInt16: String] = {
        var result: [UInt16: String] = [:]
        for (name, code) in nameToCode {
            if result[code] == nil {
                result[code] = name
            }
        }
        return result
    }()

    public static func parse(_ input: String) -> (keyCode: UInt16, modifiers: [String])? {
        let parts = input.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

        guard let keyName = parts.last, let code = nameToCode[keyName] else {
            return nil
        }

        let modifiers = Array(parts.dropLast())
        return (code, modifiers)
    }

    public static func describe(keyCode: UInt16, modifiers: [String]) -> String {
        let keyName = codeToName[keyCode] ?? "key(\(keyCode))"
        if modifiers.isEmpty {
            return keyName
        }
        return (modifiers + [keyName]).joined(separator: "+")
    }

    /// Formats a shortcut with the key symbols macOS shows in menus, such as ⌃⌥⇧⌘Espace.
    public static func displayName(keyCode: UInt16, modifiers: [String]) -> String {
        let order = ["fn", "ctrl", "opt", "shift", "cmd"]
        let symbols = modifiers
            .compactMap { modifierSymbol($0.lowercased()) }
            .sorted { (order.firstIndex(of: $0.name) ?? 0) < (order.firstIndex(of: $1.name) ?? 0) }
            .map(\.symbol)
        let key = displayKeyNames[keyCode] ?? codeToName[keyCode].map { $0.uppercased() } ?? "Touche \(keyCode)"
        if symbols.isEmpty { return key }
        // Modifier keys read better with a separator, as in "Fn + ⌥ droite".
        let separator = modifierKeyCodes.contains(keyCode) || symbols.contains("Fn") ? " + " : ""
        return symbols.joined(separator: separator) + separator + key
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static let displayKeyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "⎋", 57: "⇪",
        54: "⌘ droite", 55: "⌘", 56: "⇧", 58: "⌥", 59: "⌃",
        60: "⇧ droite", 61: "⌥ droite", 62: "⌃ droite", 63: "Fn",
    ]

    private static func modifierSymbol(_ name: String) -> (name: String, symbol: String)? {
        switch name {
        case "cmd", "command": ("cmd", "⌘")
        case "shift": ("shift", "⇧")
        case "opt", "option", "alt": ("opt", "⌥")
        case "ctrl", "control": ("ctrl", "⌃")
        case "fn", "globe": ("fn", "Fn")
        default: nil
        }
    }
}
