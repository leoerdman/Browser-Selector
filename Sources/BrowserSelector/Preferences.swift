import Foundation

final class Preferences {
    static let shared = Preferences(userDefaults: .standard)

    private enum Key: String {
        case rememberLastBrowser
        case lastBrowserBundleIdentifier
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    var rememberLastBrowser: Bool {
        get {
            if userDefaults.object(forKey: Key.rememberLastBrowser.rawValue) == nil {
                return true
            }

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
}
