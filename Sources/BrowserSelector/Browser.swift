import AppKit
import Foundation

struct Browser: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let icon: NSImage

    var id: String {
        bundleIdentifier
    }

    var shortDisplayName: String {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return "Chrome"
        case "com.google.Chrome.beta":
            return "Chrome Beta"
        case "com.google.Chrome.canary":
            return "Chrome Canary"
        case "com.google.Chrome.dev":
            return "Chrome Dev"
        case "com.google.chrome.for.testing":
            return "Chrome Test"
        default:
            return displayName
        }
    }
}
