import AppKit
import XCTest
@testable import LocalEchoLib

final class HotkeyManagerTests: XCTestCase {
    func testMonitorsHotkeyEventsFromOtherAppsAndLocalEchoItself() throws {
        let globalToken = NSObject()
        let localToken = NSObject()
        var globalHandler: ((NSEvent) -> Void)?
        var localHandler: ((NSEvent) -> NSEvent?)?
        var removedTokens: [AnyObject] = []
        var keyDownCount = 0
        var keyUpCount = 0

        let manager = HotkeyManager(
            keyCode: 49,
            addGlobalMonitor: { mask, handler in
                XCTAssertTrue(mask.contains(.keyDown))
                XCTAssertTrue(mask.contains(.keyUp))
                XCTAssertTrue(mask.contains(.flagsChanged))
                globalHandler = handler
                return globalToken
            },
            addLocalMonitor: { mask, handler in
                XCTAssertTrue(mask.contains(.keyDown))
                XCTAssertTrue(mask.contains(.keyUp))
                XCTAssertTrue(mask.contains(.flagsChanged))
                localHandler = handler
                return localToken
            },
            removeMonitor: { removedTokens.append($0 as AnyObject) }
        )

        manager.start(
            onKeyDown: { keyDownCount += 1 },
            onKeyUp: { keyUpCount += 1 }
        )

        let keyDown = try XCTUnwrap(makeKeyEvent(type: .keyDown, keyCode: 49))
        let keyUp = try XCTUnwrap(makeKeyEvent(type: .keyUp, keyCode: 49))
        globalHandler?(keyDown)
        let returnedEvent = localHandler?(keyUp)

        XCTAssertEqual(keyDownCount, 1)
        XCTAssertEqual(keyUpCount, 1)
        XCTAssertTrue(returnedEvent === keyUp)

        manager.stop()

        XCTAssertEqual(removedTokens.count, 2)
        XCTAssertTrue(removedTokens.contains { $0 === globalToken })
        XCTAssertTrue(removedTokens.contains { $0 === localToken })
    }

    func testChordStopsWhenModifiersAreReleasedBeforeMainKey() throws {
        var handler: ((NSEvent) -> Void)?
        var starts = 0
        var stops = 0
        let manager = HotkeyManager(
            keyCode: 49,
            modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue),
            addGlobalMonitor: { _, callback in handler = callback; return NSObject() },
            addLocalMonitor: { _, _ in nil },
            removeMonitor: { _ in }
        )
        manager.start(onKeyDown: { starts += 1 }, onKeyUp: { stops += 1 })

        handler?(try XCTUnwrap(makeKeyEvent(type: .keyDown, keyCode: 49, flags: [.command, .shift])))
        handler?(try XCTUnwrap(makeKeyEvent(type: .keyUp, keyCode: 49)))

        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
        manager.stop()
    }

    func testShortcutCaptureSuppressesExistingHotkey() throws {
        var handler: ((NSEvent) -> Void)?
        var starts = 0
        let manager = HotkeyManager(
            keyCode: 49,
            addGlobalMonitor: { _, callback in handler = callback; return NSObject() },
            addLocalMonitor: { _, _ in nil },
            removeMonitor: { _ in }
        )
        manager.start(onKeyDown: { starts += 1 }, onKeyUp: {})
        ShortcutCaptureGate.shared.setActive(true)
        defer {
            ShortcutCaptureGate.shared.setActive(false)
            manager.stop()
        }

        handler?(try XCTUnwrap(makeKeyEvent(type: .keyDown, keyCode: 49)))
        XCTAssertEqual(starts, 0)
    }

    func testModifierHotkeyFollowsKeyStateInsteadOfToggling() throws {
        var handler: ((NSEvent) -> Void)?
        var starts = 0
        var stops = 0
        let manager = HotkeyManager(
            keyCode: 61,
            addGlobalMonitor: { _, callback in handler = callback; return NSObject() },
            addLocalMonitor: { _, _ in nil },
            removeMonitor: { _ in }
        )
        manager.start(onKeyDown: { starts += 1 }, onKeyUp: { stops += 1 })
        defer { manager.stop() }

        let rightOptionDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x40)
        let bothOptionsDown = NSEvent.ModifierFlags(rawValue: rightOptionDown.rawValue | 0x20)
        let leftOptionDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)

        // A release without a press is ignored instead of starting a recording.
        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 61, flags: [])))
        XCTAssertEqual(starts, 0)

        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 61, flags: rightOptionDown)))
        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 61, flags: rightOptionDown)))
        XCTAssertEqual(starts, 1)

        // The left Option key does not release the right one.
        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 58, flags: bothOptionsDown)))
        XCTAssertEqual(stops, 0)

        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 61, flags: leftOptionDown)))
        XCTAssertEqual(stops, 1)
        handler?(try XCTUnwrap(makeFlagsEvent(keyCode: 61, flags: [])))
        XCTAssertEqual(stops, 1)
    }

    func testModifierKeyStateFallsBackWithoutSideBits() {
        XCTAssertTrue(HotkeyManager.isModifierKeyDown(61, in: .option))
        XCTAssertFalse(HotkeyManager.isModifierKeyDown(61, in: .command))
        XCTAssertTrue(HotkeyManager.isModifierKeyDown(63, in: .function))
        XCTAssertFalse(HotkeyManager.isModifierKeyDown(49, in: .option))
    }

    private func makeFlagsEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return nil }
        event.type = .flagsChanged
        event.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        return NSEvent(cgEvent: event)
    }

    private func makeKeyEvent(type: NSEvent.EventType, keyCode: UInt16,
                              flags: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
