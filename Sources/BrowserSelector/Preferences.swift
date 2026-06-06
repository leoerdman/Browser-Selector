import Foundation

final class Preferences {
    static let shared = Preferences(userDefaults: .standard)

    private enum Key: String {
        case rememberLastBrowser
        case lastBrowserBundleIdentifier
        case rememberDefaultPolicyVersion
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        applyMigrations()
    }

    var rememberLastBrowser: Bool {
        get {
            return userDefaults.bool(forKey: Key.rememberLastBrowser.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: Key.rememberLastBrowser.rawValue)
        }
    }

    var lastBrowserBundleIdentifier: String? {
        get {
            userDefaults.string(forKey: Key.lastBrowserBundleIdentifier.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: Key.lastBrowserBundleIdentifier.rawValue)
        }
    }

    private func applyMigrations() {
        let currentRememberDefaultPolicyVersion = 1
        let storedVersion = userDefaults.integer(forKey: Key.rememberDefaultPolicyVersion.rawValue)

        guard storedVersion < currentRememberDefaultPolicyVersion else {
            return
        }

        userDefaults.set(false, forKey: Key.rememberLastBrowser.rawValue)
        userDefaults.removeObject(forKey: Key.lastBrowserBundleIdentifier.rawValue)
        userDefaults.set(
            currentRememberDefaultPolicyVersion,
            forKey: Key.rememberDefaultPolicyVersion.rawValue
        )
    }
}
