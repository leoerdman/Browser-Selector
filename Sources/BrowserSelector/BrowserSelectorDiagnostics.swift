import Foundation

enum BrowserSelectorDiagnostics {
    private static let lock = NSLock()

    static var logFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("diagnostics.log")
    }

    static func record(_ message: String) {
        let line = "\(Self.timestamp()) \(message)\n"
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer {
                    try? handle.close()
                }

                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: logFileURL, options: .atomic)
            }
        } catch {
            NSLog("Browser Selector diagnostics write failed: \(error.localizedDescription)")
        }
    }

    static func describe(url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                URLQueryItem(name: item.name, value: item.value == nil ? nil : "redacted")
            }
        }

        if components.fragment != nil {
            components.fragment = "redacted"
        }

        return components.string ?? url.absoluteString
    }

    static func recentLines(limit: Int = 20) -> [String] {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map(String.init)
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Browser Selector", isDirectory: true)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
