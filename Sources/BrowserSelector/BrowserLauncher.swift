import AppKit
import Foundation

final class BrowserLauncher {
    private var activeProcesses: [UUID: Process] = [:]

    func open(_ url: URL, in browser: Browser, completion: @escaping (Result<Void, Error>) -> Void) {
        openInExistingBrowserWindow(url, browser: browser) { [weak self] appleScriptResult in
            switch appleScriptResult {
            case .success:
                completion(.success(()))
            case .failure:
                self?.openThroughLaunchServices(url, browser: browser, completion: completion)
            }
        }
    }

    private func openInExistingBrowserWindow(
        _ url: URL,
        browser: Browser,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let script = browser.usesChromiumTabModel
            ? chromiumNewTabScript()
            : openLocationScript()

        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: script.flatMap { ["-e", $0] } + [browser.bundleIdentifier, url.absoluteString],
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

    private func chromiumNewTabScript() -> [String] {
        [
            "on run argv",
            "set browserID to item 1 of argv",
            "set targetURL to item 2 of argv",
            "using terms from application \"Google Chrome\"",
            "tell application id browserID",
            "activate",
            "if (count of windows) = 0 then make new window",
            "tell front window",
            "set newTab to make new tab at end of tabs with properties {URL:targetURL}",
            "set active tab index to (count of tabs)",
            "end tell",
            "end tell",
            "end using terms from",
            "end run"
        ]
    }

    private func openLocationScript() -> [String] {
        [
            "on run argv",
            "set browserID to item 1 of argv",
            "set targetURL to item 2 of argv",
            "tell application id browserID",
            "activate",
            "open location targetURL",
            "end tell",
            "end run"
        ]
    }
}

private extension Browser {
    var usesChromiumTabModel: Bool {
        BrowserClassifier.isChromiumLike(bundleIdentifier: bundleIdentifier)
    }
}

private struct BrowserLaunchError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
