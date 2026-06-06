import AppKit
import CoreServices
import Foundation

enum DefaultBrowserRegistrationError: LocalizedError {
    case missingBundleIdentifier
    case launchServicesFailure(scheme: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "В bundle приложения не найден CFBundleIdentifier."
        case let .launchServicesFailure(scheme, status):
            return "LaunchServices вернул ошибку \(status) для схемы \(scheme)."
        }
    }
}

final class DefaultBrowserRegistrationService {
    var isDefaultBrowser: Bool {
        BrowserSelectorConstants.webURLSchemes.allSatisfy { scheme in
            defaultHandler(forURLScheme: scheme) == activeBundleIdentifier
        }
    }

    private var activeBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? BrowserSelectorConstants.bundleIdentifier
    }

    func registerAsDefaultBrowser() throws {
        guard !activeBundleIdentifier.isEmpty else {
            throw DefaultBrowserRegistrationError.missingBundleIdentifier
        }

        for scheme in BrowserSelectorConstants.webURLSchemes {
            let status = LSSetDefaultHandlerForURLScheme(
                scheme as CFString,
                activeBundleIdentifier as CFString
            )

            guard status == noErr else {
                throw DefaultBrowserRegistrationError.launchServicesFailure(
                    scheme: scheme,
                    status: status
                )
            }
        }
    }

    func defaultHandler(forURLScheme scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://browser-selector.local"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else {
            return nil
        }

        return Bundle(url: applicationURL)?.bundleIdentifier
    }
}
