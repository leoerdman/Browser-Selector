import AppKit
import XCTest
@testable import BrowserSelector

final class BrowserChoiceWindowControllerTests: XCTestCase {
    func testEscapeCancelsTheChooserWithoutOpeningABrowser() {
        runOnMainThread {
            let browser = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var results: [BrowserChoiceResult] = []

            let controller = BrowserChoiceWindowController(
                browsers: [browser],
                preferences: preferences
            ) { result in
                results.append(result)
            }

            guard let window = controller.window else {
                XCTFail("Expected BrowserChoiceWindowController to create a window.")
                return
            }

            window.sendEvent(Self.escapeKeyEvent(windowNumber: window.windowNumber))
            window.sendEvent(Self.escapeKeyEvent(windowNumber: window.windowNumber))

            XCTAssertEqual(results.count, 1)
            guard case .cancel = results[0] else {
                XCTFail("Expected Esc to cancel the chooser.")
                return
            }
        }
    }

    func testInsidePanelMouseDownDoesNotCancelTheChooser() {
        runOnMainThread {
            let browser = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var results: [BrowserChoiceResult] = []

            let controller = BrowserChoiceWindowController(
                browsers: [browser],
                preferences: preferences
            ) { result in
                results.append(result)
            }

            guard let window = controller.window else {
                XCTFail("Expected BrowserChoiceWindowController to create a window.")
                return
            }

            controller.cancelIfMouseDownIsOutsidePanel(
                at: NSPoint(x: window.frame.midX, y: window.frame.midY)
            )

            XCTAssertTrue(results.isEmpty)
        }
    }

    func testOutsidePanelMouseDownCancelsTheChooserWithoutOpeningABrowser() {
        runOnMainThread {
            let browser = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var results: [BrowserChoiceResult] = []

            let controller = BrowserChoiceWindowController(
                browsers: [browser],
                preferences: preferences
            ) { result in
                results.append(result)
            }

            guard let window = controller.window else {
                XCTFail("Expected BrowserChoiceWindowController to create a window.")
                return
            }

            let outsidePoint = NSPoint(x: window.frame.maxX + 1, y: window.frame.midY)
            controller.cancelIfMouseDownIsOutsidePanel(at: outsidePoint)
            controller.cancelIfMouseDownIsOutsidePanel(at: outsidePoint)

            XCTAssertEqual(results.count, 1)
            guard case .cancel = results[0] else {
                XCTFail("Expected outside panel mouse down to cancel the chooser.")
                return
            }
        }
    }

    func testArrowAndReturnOpenTheCurrentlySelectedBrowser() {
        runOnMainThread {
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let chrome = Self.makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var openedBrowserIdentifier: String?

            let controller = BrowserChoiceWindowController(
                browsers: [safari, chrome],
                preferences: preferences
            ) { result in
                if case let .open(browser) = result {
                    openedBrowserIdentifier = browser.bundleIdentifier
                }
            }

            guard let window = controller.window else {
                XCTFail("Expected BrowserChoiceWindowController to create a window.")
                return
            }

            window.sendEvent(Self.rightArrowKeyEvent(windowNumber: window.windowNumber))
            window.sendEvent(Self.returnKeyEvent(windowNumber: window.windowNumber))

            XCTAssertEqual(openedBrowserIdentifier, "com.google.Chrome")
        }
    }

    private func runOnMainThread(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.sync(execute: body)
        }
    }

    private static func makeBrowser(bundleIdentifier: String, displayName: String) -> Browser {
        Browser(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: URL(fileURLWithPath: "/Applications/\(displayName).app"),
            icon: NSImage(size: NSSize(width: 36, height: 36))
        )
    }

    private static func escapeKeyEvent(windowNumber: Int) -> NSEvent {
        keyEvent(
            windowNumber: windowNumber,
            characters: "\u{1B}",
            keyCode: 53
        )
    }

    private static func returnKeyEvent(windowNumber: Int) -> NSEvent {
        keyEvent(
            windowNumber: windowNumber,
            characters: "\r",
            keyCode: 36
        )
    }

    private static func rightArrowKeyEvent(windowNumber: Int) -> NSEvent {
        keyEvent(
            windowNumber: windowNumber,
            characters: "\u{F703}",
            keyCode: 124
        )
    }

    private static func keyEvent(windowNumber: Int, characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
