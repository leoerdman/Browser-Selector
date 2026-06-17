import Foundation

enum BrowserSelectorDiagnostics {
    private static let lock = NSLock()
    private static let timestampFormatterLock = NSLock()
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let recentLogReadByteLimit: UInt64 = 64 * 1024

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
        guard limit > 0 else {
            return []
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        var data: Data
        do {
            let fileHandle = try FileHandle(forReadingFrom: logFileURL)
            defer {
                try? fileHandle.close()
            }

            let fileSize = try fileHandle.seekToEnd()
            let readSize = min(fileSize, recentLogReadByteLimit)
            try fileHandle.seek(toOffset: fileSize - readSize)
            data = try fileHandle.readToEnd() ?? Data()
            if readSize < fileSize,
               let firstLineBreak = data.firstIndex(of: 0x0A) {
                data.removeSubrange(data.startIndex...firstLineBreak)
            }
        } catch {
            return []
        }

        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map(String.init)
    }

    private static var applicationSupportDirectory: URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupportDirectory
            .appendingPathComponent("Browser Selector", isDirectory: true)
    }

    private static func timestamp() -> String {
        timestampFormatterLock.lock()
        defer {
            timestampFormatterLock.unlock()
        }

        return timestampFormatter.string(from: Date())
    }
}
