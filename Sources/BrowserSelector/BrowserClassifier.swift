import Foundation

enum BrowserClassifier {
    private static let deniedBundleIdentifiers: Set<String> = [
        "com.hegenberg.BetterTouchTool"
    ]

    private static let exactNonChromiumBrowserBundleIdentifiers: Set<String> = [
        "app.zen-browser.zen",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.duckduckgo.macos.browser",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly"
    ]

    private static let acceptedBundlePrefixes = [
        "com.kagi.kagimacOS",
        "com.sigmaos.sigmaos",
        "company.thebrowser.",
        "org.mozilla."
    ]

    private static let acceptedNameTokens = [
        "arc",
        "brave",
        "chrome",
        "chromium",
        "comet",
        "duckduckgo",
        "edge",
        "firefox",
        "opera",
        "orion",
        "safari",
        "vivaldi",
        "zen"
    ]

    private static let chromiumBundleIdentifiers: Set<String> = [
        "ai.perplexity.comet",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.google.chrome.for.testing",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "company.thebrowser.Browser",
        "org.chromium.Chromium"
    ]

    private static let chromiumBundlePrefixes = [
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser."
    ]

    private static let exactBrowserBundleIdentifiers =
        exactNonChromiumBrowserBundleIdentifiers.union(chromiumBundleIdentifiers)

    static func isBrowser(bundleIdentifier: String, displayName: String) -> Bool {
        guard !deniedBundleIdentifiers.contains(bundleIdentifier) else {
            return false
        }

        if exactBrowserBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if acceptedBundlePrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return true
        }

        let nameTokens = Set(
            displayName
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        return acceptedNameTokens.contains { nameTokens.contains($0) }
    }

    static func isChromiumLike(bundleIdentifier: String) -> Bool {
        chromiumBundleIdentifiers.contains(bundleIdentifier)
            || chromiumBundlePrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }
}
