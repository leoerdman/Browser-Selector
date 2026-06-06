import Foundation

enum AppMetadata {
    static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
    }
}
