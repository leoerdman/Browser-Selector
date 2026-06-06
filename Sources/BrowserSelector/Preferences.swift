import Foundation

final class Preferences {
    static let shared = Preferences(userDefaults: .standard)

    private enum Key: String {
        case didShowDefaultBrowserPrompt
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
            guard rememberLastBrowser != newValue else {
                return
            }

            userDefaults.set(newValue, forKey: Key.rememberLastBrowser.rawValue)
            notifyChanged()
        }
    }

    var lastBrowserBundleIdentifier: String? {
        get {
            userDefaults.string(forKey: Key.lastBrowserBundleIdentifier.rawValue)
        }
        set {
            guard lastBrowserBundleIdentifier != newValue else {
                return
            }

            if let newValue {
                userDefaults.set(newValue, forKey: Key.lastBrowserBundleIdentifier.rawValue)
            } else {
                userDefaults.removeObject(forKey: Key.lastBrowserBundleIdentifier.rawValue)
            }
            notifyChanged()
        }
    }

    var didShowDefaultBrowserPrompt: Bool {
        get {
            userDefaults.bool(forKey: Key.didShowDefaultBrowserPrompt.rawValue)
        }
        set {
            guard didShowDefaultBrowserPrompt != newValue else {
                return
            }

            userDefaults.set(newValue, forKey: Key.didShowDefaultBrowserPrompt.rawValue)
            notifyChanged()
        }
    }

    func resetRememberedBrowserChoice() {
        rememberLastBrowser = false
        lastBrowserBundleIdentifier = nil
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .browserSelectorPreferencesDidChange, object: self)
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

extension Notification.Name {
    static let browserSelectorPreferencesDidChange = Notification.Name(
        "com.leoerdman.BrowserSelector.preferencesDidChange"
    )
}
