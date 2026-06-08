import Foundation

final class Preferences {
    static let shared = Preferences(userDefaults: .standard)

    private enum Key: String {
        case didShowDefaultBrowserPrompt
        case rememberLastBrowser
        case lastBrowserBundleIdentifier
        case rememberDefaultPolicyVersion
        case hiddenBrowserBundleIdentifiers
        case customBrowserDisplayNames
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

    var hiddenBrowserBundleIdentifiers: Set<String> {
        Set(userDefaults.stringArray(forKey: Key.hiddenBrowserBundleIdentifiers.rawValue) ?? [])
    }

    func isBrowserVisible(bundleIdentifier: String) -> Bool {
        !hiddenBrowserBundleIdentifiers.contains(bundleIdentifier)
    }

    func setBrowserVisibility(bundleIdentifier: String, isVisible: Bool) {
        let previousHiddenBundleIdentifiers = hiddenBrowserBundleIdentifiers
        var hiddenBundleIdentifiers = previousHiddenBundleIdentifiers
        let shouldClearRememberedBrowser = !isVisible && lastBrowserBundleIdentifier == bundleIdentifier

        if isVisible {
            hiddenBundleIdentifiers.remove(bundleIdentifier)
        } else {
            hiddenBundleIdentifiers.insert(bundleIdentifier)
        }

        if shouldClearRememberedBrowser {
            userDefaults.removeObject(forKey: Key.lastBrowserBundleIdentifier.rawValue)
        }

        setHiddenBrowserBundleIdentifiers(hiddenBundleIdentifiers)

        if shouldClearRememberedBrowser && hiddenBundleIdentifiers == previousHiddenBundleIdentifiers {
            notifyChanged()
        }
    }

    func customBrowserDisplayName(for bundleIdentifier: String) -> String? {
        customBrowserDisplayNames[bundleIdentifier]
    }

    func setCustomBrowserDisplayName(bundleIdentifier: String, displayName: String?) {
        var customDisplayNames = customBrowserDisplayNames
        let normalizedDisplayName = Self.normalizedCustomDisplayName(displayName)

        if let normalizedDisplayName {
            customDisplayNames[bundleIdentifier] = normalizedDisplayName
        } else {
            customDisplayNames.removeValue(forKey: bundleIdentifier)
        }

        setCustomBrowserDisplayNames(customDisplayNames)
    }

    func resetRememberedBrowserChoice() {
        let changed = rememberLastBrowser || lastBrowserBundleIdentifier != nil
        userDefaults.set(false, forKey: Key.rememberLastBrowser.rawValue)
        userDefaults.removeObject(forKey: Key.lastBrowserBundleIdentifier.rawValue)

        if changed {
            notifyChanged()
        }
    }

    func rememberBrowserChoice(bundleIdentifier: String) {
        guard rememberLastBrowser,
              lastBrowserBundleIdentifier != bundleIdentifier
        else {
            return
        }

        userDefaults.set(bundleIdentifier, forKey: Key.lastBrowserBundleIdentifier.rawValue)
        notifyChanged()
    }

    func reconcileRememberedBrowser(availableBundleIdentifiers: Set<String>) {
        reconcileHiddenBrowsers(availableBundleIdentifiers: availableBundleIdentifiers)
        reconcileCustomBrowserDisplayNames(availableBundleIdentifiers: availableBundleIdentifiers)

        guard rememberLastBrowser else {
            guard lastBrowserBundleIdentifier != nil else {
                return
            }

            userDefaults.removeObject(forKey: Key.lastBrowserBundleIdentifier.rawValue)
            notifyChanged()
            return
        }

        guard let lastBrowserBundleIdentifier,
              !availableBundleIdentifiers.contains(lastBrowserBundleIdentifier)
        else {
            return
        }

        resetRememberedBrowserChoice()
    }

    private func reconcileHiddenBrowsers(availableBundleIdentifiers: Set<String>) {
        let hiddenBundleIdentifiers = hiddenBrowserBundleIdentifiers
        let reconciledHiddenBundleIdentifiers = hiddenBundleIdentifiers.intersection(availableBundleIdentifiers)

        guard reconciledHiddenBundleIdentifiers != hiddenBundleIdentifiers else {
            return
        }

        setHiddenBrowserBundleIdentifiers(reconciledHiddenBundleIdentifiers)
    }

    private func setHiddenBrowserBundleIdentifiers(_ bundleIdentifiers: Set<String>) {
        let sortedBundleIdentifiers = bundleIdentifiers.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        let storedBundleIdentifiers = userDefaults.stringArray(forKey: Key.hiddenBrowserBundleIdentifiers.rawValue) ?? []
        guard sortedBundleIdentifiers != storedBundleIdentifiers else {
            return
        }

        if sortedBundleIdentifiers.isEmpty {
            userDefaults.removeObject(forKey: Key.hiddenBrowserBundleIdentifiers.rawValue)
        } else {
            userDefaults.set(sortedBundleIdentifiers, forKey: Key.hiddenBrowserBundleIdentifiers.rawValue)
        }
        notifyChanged()
    }

    private var customBrowserDisplayNames: [String: String] {
        guard let dictionary = userDefaults.dictionary(forKey: Key.customBrowserDisplayNames.rawValue) as? [String: String] else {
            return [:]
        }

        return dictionary.reduce(into: [String: String]()) { result, element in
            guard !element.key.isEmpty,
                  element.key.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) == nil,
                  let displayName = Self.normalizedCustomDisplayName(element.value)
            else {
                return
            }

            result[element.key] = displayName
        }
    }

    private func reconcileCustomBrowserDisplayNames(availableBundleIdentifiers: Set<String>) {
        let displayNames = customBrowserDisplayNames
        let reconciledDisplayNames = displayNames.filter { availableBundleIdentifiers.contains($0.key) }

        guard reconciledDisplayNames != displayNames else {
            return
        }

        setCustomBrowserDisplayNames(reconciledDisplayNames)
    }

    private func setCustomBrowserDisplayNames(_ displayNames: [String: String]) {
        let normalizedDisplayNames = displayNames.reduce(into: [String: String]()) { result, element in
            guard !element.key.isEmpty,
                  element.key.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) == nil,
                  let displayName = Self.normalizedCustomDisplayName(element.value)
            else {
                return
            }

            result[element.key] = displayName
        }

        guard normalizedDisplayNames != customBrowserDisplayNames else {
            return
        }

        if normalizedDisplayNames.isEmpty {
            userDefaults.removeObject(forKey: Key.customBrowserDisplayNames.rawValue)
        } else {
            userDefaults.set(normalizedDisplayNames, forKey: Key.customBrowserDisplayNames.rawValue)
        }
        notifyChanged()
    }

    private static func normalizedCustomDisplayName(_ displayName: String?) -> String? {
        guard let displayName else {
            return nil
        }

        let normalizedDisplayName = displayName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedDisplayName.isEmpty else {
            return nil
        }

        return String(normalizedDisplayName.prefix(64))
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
