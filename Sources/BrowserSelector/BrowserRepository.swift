import AppKit
import Foundation

final class BrowserRepository {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func installedBrowsers() -> [Browser] {
        let ownBundleIdentifier = AppMetadata.bundleIdentifier
        let applicationURLs = BrowserSelectorConstants.webURLSchemes
            .compactMap { URL(string: "\($0)://browser-selector.local") }
            .flatMap { workspace.urlsForApplications(toOpen: $0) }

        var seenBundleIdentifiers = Set<String>()

        return applicationURLs
            .compactMap { browser(forApplicationURL: $0) }
            .filter { browser in
                let bundleIdentifier = browser.bundleIdentifier
                guard bundleIdentifier != ownBundleIdentifier else {
                    return false
                }

                return seenBundleIdentifiers.insert(bundleIdentifier).inserted
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func browser(forApplicationURL bundleURL: URL) -> Browser? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            return nil
        }

        let displayName = localizedName(for: bundle, bundleURL: bundleURL)
        guard BrowserClassifier.isBrowser(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        ) else {
            return nil
        }

        let icon = workspace.icon(forFile: bundleURL.path)
        icon.size = NSSize(width: 36, height: 36)

        return Browser(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: bundleURL,
            icon: icon
        )
    }

    private func localizedName(for bundle: Bundle?, bundleURL: URL) -> String {
        if let displayName = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let name = bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
           !name.isEmpty {
            return name
        }

        if let displayName = bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let name = bundle?.infoDictionary?["CFBundleName"] as? String,
           !name.isEmpty {
            return name
        }

        return FileManager.default.displayName(atPath: bundleURL.path)
    }
}
