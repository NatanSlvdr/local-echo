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
