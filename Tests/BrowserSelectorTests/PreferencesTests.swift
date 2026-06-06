import XCTest
@testable import BrowserSelector

final class PreferencesTests: XCTestCase {
    func testRememberedBrowserResetClearsBothPreferenceKeys() {
        let preferences = Preferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        preferences.rememberLastBrowser = true
        preferences.lastBrowserBundleIdentifier = "com.google.Chrome"
        preferences.resetRememberedBrowserChoice()

        XCTAssertFalse(preferences.rememberLastBrowser)
        XCTAssertNil(preferences.lastBrowserBundleIdentifier)
    }
}
