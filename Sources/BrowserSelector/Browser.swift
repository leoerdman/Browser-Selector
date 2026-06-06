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
}
