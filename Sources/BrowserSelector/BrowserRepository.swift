import AppKit
import Foundation

final class BrowserRepository {
    private let workspace: NSWorkspace
    private let iconProvider: BrowserIconProviding

    init(
        workspace: NSWorkspace = .shared,
        iconProvider: BrowserIconProviding = BrowserIconProvider.shared
    ) {
        self.workspace = workspace
        self.iconProvider = iconProvider
    }

    func installedBrowsers() -> [Browser] {
        let ownBundleIdentifier = AppMetadata.bundleIdentifier
        let applicationURLs = BrowserSelectorConstants.webURLSchemes
            .compactMap { URL(string: "\($0)://browser-selector.local") }
            .flatMap { workspace.urlsForApplications(toOpen: $0) }

        BrowserSelectorDiagnostics.record(
            "repository-discover rawCount=\(applicationURLs.count) schemes=\(BrowserSelectorConstants.webURLSchemes.joined(separator: ","))"
        )

        var seenBundleIdentifiers = Set<String>()

        let browsers = applicationURLs
            .compactMap { browser(forApplicationURL: $0) }
            .filter { browser in
                let bundleIdentifier = browser.bundleIdentifier
                guard bundleIdentifier != ownBundleIdentifier else {
                    BrowserSelectorDiagnostics.record("repository-filter self-skip \(bundleIdentifier)")
                    return false
                }

                return seenBundleIdentifiers.insert(bundleIdentifier).inserted
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }

        BrowserSelectorDiagnostics.record(
            "repository-discover acceptedCount=\(browsers.count)"
        )
        return browsers
    }

    private func browser(forApplicationURL bundleURL: URL) -> Browser? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            BrowserSelectorDiagnostics.record("repository-skip no-bundle-or-id \(bundleURL.lastPathComponent)")
            return nil
        }

        let displayName = localizedName(for: bundle, bundleURL: bundleURL)
        guard BrowserClassifier.isBrowser(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        ) else {
            BrowserSelectorDiagnostics.record(
                "repository-reject id=\(bundleIdentifier) name=\(displayName)"
            )
            return nil
        }

        BrowserSelectorDiagnostics.record(
            "repository-accept id=\(bundleIdentifier) name=\(displayName) path=\(bundleURL.path)"
        )
        let icon = iconProvider.icon(forApplicationAt: bundleURL)

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
