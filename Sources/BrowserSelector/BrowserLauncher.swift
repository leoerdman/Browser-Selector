import AppKit
import Foundation

final class BrowserLauncher {
    private enum LaunchFallbackPolicy {
        case allowLaunchServices
        case requireUserAction(Error)
    }

    private let appleScriptQueue = DispatchQueue(label: "com.leoerdman.BrowserSelector.appleScript")
    private var activeProcesses: [UUID: Process] = [:]

    func open(_ url: URL, in browser: Browser, completion: @escaping (Result<Void, Error>) -> Void) {
        openInExistingBrowserWindow(url, browser: browser) { [weak self] primaryResult in
            switch primaryResult {
            case .success:
                completion(.success(()))
                return
            case let .failure(error):
                switch Self.fallbackPolicy(for: error) {
                case .allowLaunchServices:
                    break
                case let .requireUserAction(error):
                    completion(.failure(error))
                    return
                }
            }

            self?.openLocation(url, browser: browser) { [weak self] openLocationResult in
                switch openLocationResult {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    switch Self.fallbackPolicy(for: error) {
                    case .allowLaunchServices:
                        self?.openThroughLaunchServices(url, browser: browser, completion: completion)
                    case let .requireUserAction(error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private func openInExistingBrowserWindow(
        _ url: URL,
        browser: Browser,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard browser.usesChromiumTabModel else {
            openLocation(url, browser: browser, completion: completion)
            return
        }

        runAppleScript(
            chromiumNewTabScript(
                bundleIdentifier: browser.bundleIdentifier,
                urlString: url.absoluteString
            ),
            completion: completion
        )
    }

    private func openLocation(
        _ url: URL,
        browser: Browser,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runAppleScript(
            openLocationScript(
                bundleIdentifier: browser.bundleIdentifier,
                urlString: url.absoluteString
            ),
            completion: completion
        )
    }

    private func openThroughLaunchServices(
        _ url: URL,
        browser: Browser,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-b", browser.bundleIdentifier, url.absoluteString],
            completion: completion
        )
    }

    private func runAppleScript(
        _ source: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        appleScriptQueue.async {
            guard let appleScript = NSAppleScript(source: source) else {
                DispatchQueue.main.async {
                    completion(.failure(BrowserLaunchError(message: "Не удалось подготовить AppleScript.")))
                }
                return
            }

            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async {
                if let errorInfo {
                    completion(.failure(BrowserLaunchError(errorInfo: errorInfo)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let process = Process()
        let processID = UUID()
        let standardError = Pipe()
        let standardOutput = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardError = standardError
        process.standardOutput = standardOutput

        process.terminationHandler = { [weak self, standardError, standardOutput] terminatedProcess in
            let outputMessage = Self.readString(from: standardOutput)
            let errorMessage = Self.readString(from: standardError)

            DispatchQueue.main.async {
                self?.activeProcesses[processID] = nil

                if terminatedProcess.terminationStatus == 0 {
                    completion(.success(()))
                    return
                }

                let message = [errorMessage, outputMessage]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                completion(
                    .failure(
                        BrowserLaunchError(
                            message: message.isEmpty
                                ? "\(executableURL.lastPathComponent) завершился с кодом \(terminatedProcess.terminationStatus)."
                                : message
                        )
                    )
                )
            }
        }

        do {
            activeProcesses[processID] = process
            try process.run()
        } catch {
            activeProcesses[processID] = nil
            completion(.failure(error))
        }
    }

    private static func readString(from pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func fallbackPolicy(for error: Error) -> LaunchFallbackPolicy {
        guard let launchError = error as? BrowserLaunchError,
              launchError.isAutomationPermissionDenied
        else {
            return .allowLaunchServices
        }

        return .requireUserAction(error)
    }

    private func chromiumNewTabScript(bundleIdentifier: String, urlString: String) -> String {
        let browserID = Self.appleScriptLiteral(bundleIdentifier)
        let targetURL = Self.appleScriptLiteral(urlString)

        return """
        using terms from application id \(browserID)
        tell application id \(browserID)
            activate
            if (count of windows) = 0 then make new window
            tell front window
                set newTab to make new tab at end of tabs with properties {URL:\(targetURL)}
                set active tab index to (count of tabs)
            end tell
        end tell
        end using terms from
        """
    }

    private func openLocationScript(bundleIdentifier: String, urlString: String) -> String {
        let browserID = Self.appleScriptLiteral(bundleIdentifier)
        let targetURL = Self.appleScriptLiteral(urlString)

        return """
        tell application id \(browserID)
            activate
            open location \(targetURL)
        end tell
        """
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")

        return "\"\(escapedValue)\""
    }
}

private extension Browser {
    var usesChromiumTabModel: Bool {
        BrowserClassifier.isChromiumLike(bundleIdentifier: bundleIdentifier)
    }
}

private struct BrowserLaunchError: LocalizedError {
    let message: String
    let errorNumber: Int?

    init(message: String) {
        self.message = message
        self.errorNumber = nil
    }

    init(errorInfo: NSDictionary) {
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        let number = errorInfo[NSAppleScript.errorNumber] as? NSNumber
        self.errorNumber = number?.intValue

        if let message, let number {
            self.message = "\(message) (\(number.intValue))"
        } else if let message {
            self.message = message
        } else if let number {
            self.message = "AppleScript завершился с ошибкой \(number.intValue)."
        } else {
            self.message = "AppleScript завершился с неизвестной ошибкой."
        }
    }

    var errorDescription: String? {
        message
    }

    var isAutomationPermissionDenied: Bool {
        errorNumber == -1743
    }
}
