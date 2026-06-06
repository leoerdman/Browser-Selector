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

    private func makePreferences() -> Preferences {
        Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    }
}
