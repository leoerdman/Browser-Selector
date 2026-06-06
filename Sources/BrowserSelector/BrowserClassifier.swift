import Foundation

enum BrowserClassifier {
    private static let deniedBundleIdentifiers: Set<String> = [
        "com.hegenberg.BetterTouchTool"
    ]

    private static let exactBrowserBundleIdentifiers: Set<String> = [
        "ai.perplexity.comet",
        "app.zen-browser.zen",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.duckduckgo.macos.browser",
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
        "org.chromium.Chromium",
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

        let normalizedName = displayName.lowercased()
        return acceptedNameTokens.contains { normalizedName.contains($0) }
    }

    static func isChromiumLike(bundleIdentifier: String) -> Bool {
        let exactChromiumBrowser = exactBrowserBundleIdentifiers.contains(bundleIdentifier)
            && !bundleIdentifier.hasPrefix("com.apple.Safari")
            && !bundleIdentifier.hasPrefix("org.mozilla.")
            && bundleIdentifier != "com.duckduckgo.macos.browser"

        return exactChromiumBrowser
            || bundleIdentifier.hasPrefix("com.google.Chrome")
            || bundleIdentifier == "com.google.chrome.for.testing"
            || bundleIdentifier.hasPrefix("com.microsoft.edgemac")
            || bundleIdentifier.hasPrefix("com.brave.Browser")
            || bundleIdentifier.hasPrefix("com.vivaldi.Vivaldi")
            || bundleIdentifier.hasPrefix("company.thebrowser.")
            || bundleIdentifier == "ai.perplexity.comet"
            || bundleIdentifier == "org.chromium.Chromium"
    }
}
