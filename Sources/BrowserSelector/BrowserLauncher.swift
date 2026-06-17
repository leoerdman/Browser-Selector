import AppKit
import Foundation

final class BrowserLauncher {
    private enum LaunchFallbackPolicy {
        case allowLaunchServices
        case requireUserAction(Error)
    }

    private enum Timeout {
        static let appleScript: TimeInterval = 12
        static let process: TimeInterval = 10
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
            BrowserLaunchScriptFactory.chromiumNewTabScript(
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
            BrowserLaunchScriptFactory.openLocationScript(
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
            let result = Self.executeAppleScriptWithTimeout(source, timeout: Timeout.appleScript)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func executeAppleScriptWithTimeout(
        _ source: String,
        timeout: TimeInterval
    ) -> Result<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var result: Result<Void, Error>?

        DispatchQueue.global(qos: .userInitiated).async {
            guard let appleScript = NSAppleScript(source: source) else {
                resultLock.lock()
                result = .failure(BrowserLaunchError(message: "Не удалось подготовить AppleScript."))
                resultLock.unlock()
                semaphore.signal()
                return
            }

            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)

            resultLock.lock()
            if let errorInfo {
                result = .failure(BrowserLaunchError(errorInfo: errorInfo))
            } else {
                result = .success(())
            }
            resultLock.unlock()
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failure(BrowserLaunchError(message: "AppleScript не ответил за \(Int(timeout)) секунд."))
        }

        resultLock.lock()
        defer {
            resultLock.unlock()
        }

        return result ?? .failure(BrowserLaunchError(message: "AppleScript завершился без результата."))
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

        let timeoutWorkItem = DispatchWorkItem { [weak process] in
            guard let process,
                  process.isRunning
            else {
                return
            }

            process.terminate()
        }

        process.terminationHandler = { [weak self, standardError, standardOutput] terminatedProcess in
            timeoutWorkItem.cancel()
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
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Timeout.process,
                execute: timeoutWorkItem
            )
        } catch {
            timeoutWorkItem.cancel()
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
