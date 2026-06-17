import AppKit
import CoreServices
import Foundation

enum DefaultBrowserRegistrationState {
    case alreadyDefault
    case requestedSystemConfirmation
}

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
    private let promptPendingStatus: OSStatus = -54

    var isDefaultBrowser: Bool {
        guard let activeBundleIdentifier else {
            return false
        }

        return BrowserSelectorConstants.webURLSchemes.allSatisfy { scheme in
            defaultHandler(forURLScheme: scheme) == activeBundleIdentifier
        } && BrowserSelectorConstants.webContentTypes.allSatisfy { contentType in
            defaultHandler(forContentType: contentType) == activeBundleIdentifier
        }
    }

    private var activeBundleIdentifier: String? {
        AppMetadata.bundleIdentifier
    }

    func requestDefaultBrowserRegistration() throws -> DefaultBrowserRegistrationState {
        guard let activeBundleIdentifier,
              !activeBundleIdentifier.isEmpty
        else {
            throw DefaultBrowserRegistrationError.missingBundleIdentifier
        }

        guard !isDefaultBrowser else {
            return .alreadyDefault
        }

        for scheme in BrowserSelectorConstants.webURLSchemes {
            guard defaultHandler(forURLScheme: scheme) != activeBundleIdentifier else {
                continue
            }

            let status = LSSetDefaultHandlerForURLScheme(
                scheme as CFString,
                activeBundleIdentifier as CFString
            )

            if status == promptPendingStatus {
                return .requestedSystemConfirmation
            }

            guard status == noErr else {
                throw DefaultBrowserRegistrationError.launchServicesFailure(
                    scheme: scheme,
                    status: status
                )
            }
        }

        for contentType in BrowserSelectorConstants.webContentTypes {
            guard defaultHandler(forContentType: contentType) != activeBundleIdentifier else {
                continue
            }

            let status = LSSetDefaultRoleHandlerForContentType(
                contentType as CFString,
                .viewer,
                activeBundleIdentifier as CFString
            )

            guard status == noErr else {
                throw DefaultBrowserRegistrationError.launchServicesFailure(
                    scheme: contentType,
                    status: status
                )
            }
        }

        return isDefaultBrowser ? .alreadyDefault : .requestedSystemConfirmation
    }

    func defaultHandler(forURLScheme scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://browser-selector.local"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else {
            return nil
        }

        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    func defaultHandler(forContentType contentType: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(contentType as CFString, .viewer)?
            .takeRetainedValue() as String?
    }
}
