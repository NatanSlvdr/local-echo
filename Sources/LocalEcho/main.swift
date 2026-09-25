import AppKit
import Foundation
import LocalEchoLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = LocalEcho.version

func printUsage() {
    print("""
    Local-Echo v\(version) — Push-to-talk voice dictation for macOS

    USAGE:
        local-echo start              Start the dictation daemon
        local-echo set-hotkey <key>   Set the push-to-talk hotkey
        local-echo get-hotkey         Show current hotkey
        local-echo set-model <id>     Set the speech model
        local-echo set-cleanup <id|off>  Set transcript cleanup
        local-echo download-model [id]  Download a model
        local-echo status             Show configuration and status
        local-echo --help             Show this help message

    HOTKEY EXAMPLES:
        local-echo set-hotkey globe             Globe/fn key (default)
        local-echo set-hotkey rightoption        Right Option key
        local-echo set-hotkey f5                 F5 key
        local-echo set-hotkey ctrl+space         Ctrl + Space

    AVAILABLE MODELS:
        \(Config.supportedModels.joined(separator: ", "))
    CLEANUP MODEL:
        \(ModelCatalog.cleanup.id) (or off)
    """)
}

func cmdSetCleanup(_ id: String) {
    guard id == "off" || id == ModelCatalog.cleanup.id else {
        print("Error: Unknown cleanup model '\(id)'")
        exit(1)
    }
    var config = Config.load()
    config.cleanupModel = id == "off" ? nil : id
    do {
        try config.save()
        print("Cleanup set to: \(id)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

@MainActor func cmdStart() {
    let instanceLock: DaemonInstanceLock
    do {
        guard let acquiredLock = try DaemonInstanceLock.acquire() else {
            fputs("Local-Echo is already running.\n", stderr)
            exit(0)
        }
        instanceLock = acquiredLock
    } catch {
        fputs("Error: could not acquire the Local-Echo instance lock: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    let app = NSApplication.shared
    let terminationResult = LegacyInstanceTerminator.terminatePreviousInstances()
    if terminationResult.foundCount > 0 {
        print("Stopped \(terminationResult.foundCount) previous Local-Echo instance(s).")
    }
    if !terminationResult.remainingProcessIdentifiers.isEmpty {
        let processList = terminationResult.remainingProcessIdentifiers
            .map(String.init)
            .joined(separator: ", ")
        fputs("Could not stop previous Local-Echo process(es): \(processList).\n", stderr)
        exit(0)
    }
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    // A model worker that exits must not end the app when a request writes to its closed pipe.
    signal(SIGPIPE, SIG_IGN)
    signal(SIGINT) { _ in
        print("\nStopping Local-Echo...")
        exit(0)
    }

    withExtendedLifetime(instanceLock) {
        app.run()
    }
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'local-echo --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetModel(_ size: String) {
    guard Config.supportedModels.contains(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \(Config.supportedModels.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.modelSize = size

    do {
        try config.save()
        print("Model set to: \(size)")
        if !ModelCatalog.isInstalled(size) {
            print("Model will be downloaded on next start.")
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    let config = Config.load()
    let desc = config.hotkeySummary()
    print("Current hotkey: \(desc)")
}

func cmdDownloadModel(_ size: String) {
    guard let model = ModelCatalog.model(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \((Config.supportedModels + [ModelCatalog.cleanup.id]).joined(separator: ", "))")
        exit(1)
    }
    do {
        try ModelDownloader.download(model)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = config.hotkeySummary()

    print("Local-Echo v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Model:       \(config.modelSize)")
    print("Model ready: \(ModelCatalog.isInstalled(config.modelSize) ? "yes" : "no")")
    print("Cleanup:     \(config.cleanupModel ?? "off")")
    if let cleanup = config.cleanupModel {
        print("Cleanup ready: \(ModelCatalog.isInstalled(cleanup) ? "yes" : "no")")
    }
    print("Whisper server: \(BundledBinaries.whisperServer != nil ? "yes" : "no")")
    print("Language:    Auto-detect")
    print("Toggle:      \(config.usesToggleMode ? "on (press to start/stop)" : "off (hold to talk)")")
}

let args = CommandLine.arguments
let rawCommand = args.count > 1 ? args[1] : nil
let command: String? = {
    if let r = rawCommand, r.hasPrefix("-psn_") { return "start" }
    // Finder, Launchpad, and login items open the app without arguments.
    if rawCommand == nil, AppBundleLaunch.isExecutableInsideAppBundle(args[0]) { return "start" }
    return rawCommand
}()

switch command {
case "start":
    if AppBundleLaunch.relaunchThroughAppBundleIfNeeded() {
        exit(0)
    }
    MainActor.assumeIsolated { cmdStart() }
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: local-echo set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-model":
    guard args.count > 2 else {
        print("Usage: local-echo set-model <size>")
        exit(1)
    }
    cmdSetModel(args[2])
case "set-cleanup":
    guard args.count > 2 else {
        print("Usage: local-echo set-cleanup <id|off>")
        exit(1)
    }
    cmdSetCleanup(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "download-model":
    let size = args.count > 2 ? args[2] : Config.defaultConfig.modelSize
    cmdDownloadModel(size)
case "status":
    cmdStatus()
case "--help", "-h", "help":
    printUsage()
case nil:
    printUsage()
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
