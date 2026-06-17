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

    func testChooserWindowUsesBorderlessMinimalPanelChrome() {
        runOnMainThread {
            let browser = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

            let controller = BrowserChoiceWindowController(
                browsers: [browser],
                preferences: preferences
            ) { _ in }

            guard let window = controller.window else {
                XCTFail("Expected BrowserChoiceWindowController to create a window.")
                return
            }

            XCTAssertTrue(window.styleMask.contains(.borderless))
            XCTAssertFalse(window.styleMask.contains(.titled))
            XCTAssertFalse(window.styleMask.contains(.closable))
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

    func testReturnOpensFirstBrowserFromProvidedOrderWithoutWindowLevelReordering() {
        runOnMainThread {
            let chrome = Self.makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            preferences.rememberLastBrowser = true
            preferences.lastBrowserBundleIdentifier = "com.apple.Safari"
            var openedBrowserIdentifier: String?

            let controller = BrowserChoiceWindowController(
                browsers: [chrome, safari],
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

            window.sendEvent(Self.returnKeyEvent(windowNumber: window.windowNumber))

            XCTAssertEqual(openedBrowserIdentifier, "com.google.Chrome")
        }
    }

    func testBrowserContextMenuHidePersistsHiddenBrowserAndKeepsChooserOpen() {
        runOnMainThread {
            let chrome = Self.makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var results: [BrowserChoiceResult] = []

            let controller = BrowserChoiceWindowController(
                browsers: [chrome, safari],
                preferences: preferences
            ) { result in
                results.append(result)
            }

            let chromeButton = self.tryFindBrowserTileButton(
                in: controller,
                bundleIdentifier: "com.google.Chrome"
            )
            guard let hideItem = chromeButton?.menu?.items.first(where: { $0.title == "Скрыть" }) else {
                XCTFail("Expected browser tile context menu to contain Скрыть.")
                return
            }

            guard let action = hideItem.action else {
                XCTFail("Expected Hide menu item to have an action.")
                return
            }

            NSApp.sendAction(action, to: hideItem.target, from: hideItem)

            XCTAssertFalse(preferences.isBrowserVisible(bundleIdentifier: "com.google.Chrome"))
            XCTAssertTrue(results.isEmpty)
            XCTAssertNil(
                self.tryFindBrowserTileButton(
                    in: controller,
                    bundleIdentifier: "com.google.Chrome"
                )
            )
            XCTAssertNotNil(
                self.tryFindBrowserTileButton(
                    in: controller,
                    bundleIdentifier: "com.apple.Safari"
                )
            )
        }
    }

    func testHidingBrowserBeforeSelectedOneKeepsSameLogicalSelectionForReturn() {
        runOnMainThread {
            let chrome = Self.makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            let firefox = Self.makeBrowser(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox")
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            var openedBrowserIdentifier: String?

            let controller = BrowserChoiceWindowController(
                browsers: [chrome, firefox, safari],
                preferences: preferences
            ) { result in
                if case let .open(browser) = result {
                    openedBrowserIdentifier = browser.bundleIdentifier
                }
            }

            guard let window = controller.window,
                  let chromeButton = self.tryFindBrowserTileButton(
                    in: controller,
                    bundleIdentifier: "com.google.Chrome"
                  ),
                  let hideItem = chromeButton.menu?.items.first(where: { $0.title == "Скрыть" }),
                  let hideAction = hideItem.action
            else {
                XCTFail("Expected chooser window and Chrome Hide item.")
                return
            }

            window.sendEvent(Self.rightArrowKeyEvent(windowNumber: window.windowNumber))
            window.sendEvent(Self.rightArrowKeyEvent(windowNumber: window.windowNumber))
            NSApp.sendAction(hideAction, to: hideItem.target, from: hideItem)
            window.sendEvent(Self.returnKeyEvent(windowNumber: window.windowNumber))

            XCTAssertEqual(openedBrowserIdentifier, "com.apple.Safari")
        }
    }

    func testCustomBrowserDisplayNameIsRenderedInTile() {
        runOnMainThread {
            let chrome = Self.makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
            preferences.setCustomBrowserDisplayName(bundleIdentifier: "com.google.Chrome", displayName: "Work")

            let controller = BrowserChoiceWindowController(
                browsers: [chrome],
                preferences: preferences
            ) { _ in }

            let labelText = self.allSubviews(of: controller.window?.contentView ?? NSView())
                .compactMap { ($0 as? NSTextField)?.stringValue }

            XCTAssertTrue(labelText.contains("Work"))
            XCTAssertFalse(labelText.contains("Chrome"))
        }
    }

    func testBrowserContextMenuIncludesRenameBeforeHide() {
        runOnMainThread {
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

            let controller = BrowserChoiceWindowController(
                browsers: [safari],
                preferences: preferences
            ) { _ in }

            let safariButton = self.tryFindBrowserTileButton(
                in: controller,
                bundleIdentifier: "com.apple.Safari"
            )

            XCTAssertEqual(safariButton?.menu?.items.first?.title, "Переименовать")
            XCTAssertEqual(safariButton?.menu?.items.dropFirst().first?.title, "Скрыть")
        }
    }

    func testBrowserContextMenuDoesNotAllowHidingLastVisibleBrowser() {
        runOnMainThread {
            let safari = Self.makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
            let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

            let controller = BrowserChoiceWindowController(
                browsers: [safari],
                preferences: preferences
            ) { _ in }

            let safariButton = self.tryFindBrowserTileButton(
                in: controller,
                bundleIdentifier: "com.apple.Safari"
            )
            guard let hideItem = safariButton?.menu?.items.first(where: { $0.title == "Скрыть" }) else {
                XCTFail("Expected browser tile context menu to contain Скрыть.")
                return
            }

            XCTAssertFalse(hideItem.isEnabled)
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

    private func tryFindBrowserTileButton(
        in controller: BrowserChoiceWindowController,
        bundleIdentifier: String
    ) -> BrowserTileButton? {
        guard let contentView = controller.window?.contentView else {
            return nil
        }

        return allSubviews(of: contentView)
            .compactMap { $0 as? BrowserTileButton }
            .first { $0.browserBundleIdentifier == bundleIdentifier }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
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
