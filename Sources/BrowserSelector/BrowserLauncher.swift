import AppKit
import Darwin
import Foundation

final class BrowserLauncher {
    private enum LaunchFallbackPolicy {
        case allowLaunchServices
        case requireUserAction(Error)
    }

    private enum Timeout {
        static let appleScript: TimeInterval = 12
        static let process: TimeInterval = 10
        static let processTerminationGrace: TimeInterval = 2
    }

    private let appleScriptQueue = DispatchQueue(label: "com.leoerdman.BrowserSelector.appleScript")
    private let appleScriptExecutionLimiter = DispatchSemaphore(value: 1)
    private let processStateQueue = DispatchQueue(label: "com.leoerdman.BrowserSelector.processState")
    private var activeProcesses: [UUID: Process] = [:]

    func open(_ url: URL, in browser: Browser, completion: @escaping (Result<Void, Error>) -> Void) {
        openInExistingBrowserWindow(url, browser: browser) { [weak self] primaryResult in
            guard let self else {
                completion(.failure(BrowserLaunchError(message: "Browser launcher was released before opening the link.")))
                return
            }

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

            self.openLocation(url, browser: browser) { [weak self] openLocationResult in
                guard let self else {
                    completion(.failure(BrowserLaunchError(message: "Browser launcher was released before fallback opening the link.")))
                    return
                }

                switch openLocationResult {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    switch Self.fallbackPolicy(for: error) {
                    case .allowLaunchServices:
                        self.openThroughLaunchServices(url, browser: browser, completion: completion)
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
            let result = self.executeAppleScriptWithTimeout(source, timeout: Timeout.appleScript)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func executeAppleScriptWithTimeout(
        _ source: String,
        timeout: TimeInterval
    ) -> Result<Void, Error> {
        guard appleScriptExecutionLimiter.wait(timeout: .now()) == .success else {
            return .failure(
                BrowserLaunchError(
                    message: "Предыдущий AppleScript еще не завершился; ссылка будет открыта через LaunchServices."
                )
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var result: Result<Void, Error>?

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                self.appleScriptExecutionLimiter.signal()
                semaphore.signal()
            }

            guard let appleScript = NSAppleScript(source: source) else {
                resultLock.lock()
                result = .failure(BrowserLaunchError(message: "Не удалось подготовить AppleScript."))
                resultLock.unlock()
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

        let timeoutLock = NSLock()
        var didTimeOut = false
        func markTimedOut() {
            timeoutLock.lock()
            didTimeOut = true
            timeoutLock.unlock()
        }
        func processTimedOut() -> Bool {
            timeoutLock.lock()
            defer {
                timeoutLock.unlock()
            }
            return didTimeOut
        }

        let timeoutWorkItem = DispatchWorkItem { [weak process] in
            guard let process,
                  process.isRunning
            else {
                return
            }

            markTimedOut()
            process.terminate()

            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Timeout.processTerminationGrace
            ) { [weak process] in
                guard let process,
                      process.isRunning
                else {
                    return
                }

                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        process.terminationHandler = { [weak self, standardError, standardOutput] terminatedProcess in
            timeoutWorkItem.cancel()
            let outputMessage = Self.readString(from: standardOutput)
            let errorMessage = Self.readString(from: standardError)
            let timedOut = processTimedOut()

            DispatchQueue.main.async {
                self?.untrackProcess(identifier: processID)

                if terminatedProcess.terminationStatus == 0 {
                    completion(.success(()))
                    return
                }

                let message = [errorMessage, outputMessage]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let failureMessage: String
                if timedOut {
                    failureMessage = "\(executableURL.lastPathComponent) не ответил за \(Int(Timeout.process)) секунд и был остановлен."
                } else if message.isEmpty {
                    failureMessage = "\(executableURL.lastPathComponent) завершился с кодом \(terminatedProcess.terminationStatus)."
                } else {
                    failureMessage = message
                }

                completion(
                    .failure(
                        BrowserLaunchError(message: failureMessage)
                    )
                )
            }
        }

        do {
            trackProcess(process, identifier: processID)
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Timeout.process,
                execute: timeoutWorkItem
            )
        } catch {
            timeoutWorkItem.cancel()
            untrackProcess(identifier: processID)
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private func trackProcess(_ process: Process, identifier: UUID) {
        processStateQueue.sync {
            activeProcesses[identifier] = process
        }
    }

    private func untrackProcess(identifier: UUID) {
        processStateQueue.sync {
            activeProcesses[identifier] = nil
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
