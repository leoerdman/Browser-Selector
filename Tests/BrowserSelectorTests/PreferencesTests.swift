import XCTest
@testable import BrowserSelector

final class PreferencesTests: XCTestCase {
    func testRememberedBrowserResetClearsBothPreferenceKeys() {
        let preferences = makePreferences()

        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"
        preferences.resetRememberedBrowserChoice()

        XCTAssertFalse(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }

    func testRememberBrowserChoiceOnlyPersistsWhenRememberingIsEnabled() {
        let preferences = makePreferences()

        preferences.rememberBrowserChoice(bundleIdentifier: "com.apple.Safari")
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)

        preferences.rememberLastBrowser = true
        preferences.rememberBrowserChoice(bundleIdentifier: "com.apple.Safari")

        XCTAssertEqual(preferences.lastBrowserBundleIdentifier, "com.apple.Safari")
    }

    func testResetRememberedBrowserChoiceEmitsOneNotificationForAtomicStateChange() {
        let preferences = makePreferences()
        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"

        var notificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .browserSelectorPreferencesDidChange,
            object: preferences,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        preferences.resetRememberedBrowserChoice()

        XCTAssertEqual(notificationCount, 1)
        XCTAssertFalse(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }

    func testReconcileRememberedBrowserKeepsAvailableChoiceAndClearsStaleChoice() {
        let preferences = makePreferences()
        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"

        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: ["com.apple.Safari", "com.google.Chrome"]
        )
        XCTAssertTrue(preferences.rememberLastBrowser)
        XCTAssertEqual(preferences.lastBrowserBundleIdentifier, "com.google.Chrome")

        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: ["com.apple.Safari"]
        )
        XCTAssertFalse(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }

    func testReconcileRememberedBrowserClearsIdentifierWhenRememberingIsDisabled() {
        let preferences = makePreferences()
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"

        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: ["com.google.Chrome"]
        )

        XCTAssertFalse(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }

    func testBrowserVisibilityPersistsHiddenBrowserIdentifiers() {
        let preferences = makePreferences()

        XCTAssertTrue(preferences.isBrowserVisible(bundleIdentifier: "com.google.Chrome"))

        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: false)
        XCTAssertFalse(preferences.isBrowserVisible(bundleIdentifier: "com.google.Chrome"))
        XCTAssertEqual(preferences.hiddenBrowserBundleIdentifiers, Set(["com.google.Chrome"]))

        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: true)
        XCTAssertTrue(preferences.isBrowserVisible(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(preferences.hiddenBrowserBundleIdentifiers.isEmpty)
    }

    func testHidingRememberedBrowserClearsRememberedIdentifier() {
        let preferences = makePreferences()
        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"

        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: false)

        XCTAssertTrue(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }

    func testHidingAlreadyHiddenRememberedBrowserStillEmitsPreferenceChange() {
        let preferences = makePreferences()
        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: false)
        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"

        var notificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .browserSelectorPreferencesDidChange,
            object: preferences,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: false)

        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
        XCTAssertEqual(notificationCount, 1)
    }

    func testReconcileRememberedBrowserRemovesHiddenBrowsersThatAreNoLongerInstalled() {
        let preferences = makePreferences()
        preferences.setBrowserVisibility(bundleIdentifier: "com.google.Chrome", isVisible: false)
        preferences.setBrowserVisibility(bundleIdentifier: "org.mozilla.firefox", isVisible: false)

        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: ["org.mozilla.firefox"]
        )

        XCTAssertEqual(preferences.hiddenBrowserBundleIdentifiers, Set(["org.mozilla.firefox"]))
    }

    func testCustomBrowserDisplayNamePersistsAndNormalizesWhitespace() {
        let preferences = makePreferences()
        let browser = Browser(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            icon: NSImage(size: NSSize(width: 36, height: 36))
        )

        XCTAssertEqual(browser.displayName(preferences: preferences), "Chrome")

        preferences.setCustomBrowserDisplayName(
            bundleIdentifier: "com.google.Chrome",
            displayName: "  Work\nChrome  "
        )

        XCTAssertEqual(preferences.customBrowserDisplayName(for: "com.google.Chrome"), "Work Chrome")
        XCTAssertEqual(browser.displayName(preferences: preferences), "Work Chrome")

        preferences.setCustomBrowserDisplayName(bundleIdentifier: "com.google.Chrome", displayName: "   ")
        XCTAssertNil(preferences.customBrowserDisplayName(for: "com.google.Chrome"))
        XCTAssertEqual(browser.displayName(preferences: preferences), "Chrome")
    }

    func testCustomBrowserDisplayNameNormalizesRawStoredDictionaryValues() {
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.set(
            ["com.google.Chrome": "  Work\nChrome  "],
            forKey: "customBrowserDisplayNames"
        )
        let preferences = Preferences(userDefaults: userDefaults)

        XCTAssertEqual(preferences.customBrowserDisplayName(for: "com.google.Chrome"), "Work Chrome")
    }

    func testReconcileRememberedBrowserRemovesCustomNamesForBrowsersThatAreNoLongerInstalled() {
        let preferences = makePreferences()
        preferences.setCustomBrowserDisplayName(bundleIdentifier: "com.google.Chrome", displayName: "Work")
        preferences.setCustomBrowserDisplayName(bundleIdentifier: "org.mozilla.firefox", displayName: "Fox")

        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: ["org.mozilla.firefox"]
        )

        XCTAssertNil(preferences.customBrowserDisplayName(for: "com.google.Chrome"))
        XCTAssertEqual(preferences.customBrowserDisplayName(for: "org.mozilla.firefox"), "Fox")
    }

    private func makePreferences() -> Preferences {
        Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    }
}
