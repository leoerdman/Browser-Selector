import Foundation

enum BrowserSelectorDiagnostics {
    /// Maximum age of a log entry. Entries older than this are pruned from
    /// the diagnostics log on a debounced schedule. SSOT for log retention.
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    private static let lock = NSLock()
    private static let timestampFormatterLock = NSLock()
    private static let pruneCheckLock = NSLock()
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let recentLogReadByteLimit: UInt64 = 64 * 1024

    /// Minimum interval between prune passes. Pruning is O(n) over the log
    /// file; we debounce it so rapid bursts of `record(_:)` calls do not
    /// re-parse the whole file on every line.
    private static let pruneDebounceInterval: TimeInterval = 60
    private static var lastPruneCheckAt: Date?

    static var logFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("diagnostics.log")
    }

    static func record(_ message: String) {
        let line = "\(Self.timestamp()) \(message)\n"
        lock.lock()
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
        lock.unlock()

        pruneOldEntriesIfNeeded()
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

    /// Prunes the diagnostics log to entries no older than `retentionInterval`.
    /// Visible for testing: callers may force a prune pass and verify the
    /// resulting file contents.
    static func pruneOldEntries(now: Date = Date()) {
        pruneOldEntries(at: logFileURL, now: now)
    }

    /// Prunes the diagnostics log at `fileURL` to entries no older than
    /// `retentionInterval`. Public for testing with an isolated log file.
    static func pruneOldEntries(at fileURL: URL, now: Date = Date()) {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let cutoff = now.addingTimeInterval(-retentionInterval)
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }

        let keptLines = contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { line in
                Self.timestamp(from: String(line)).map { $0 >= cutoff } ?? true
            }

        let prunedContents = keptLines.isEmpty ? "" : "\(keptLines.joined(separator: "\n"))\n"
        try? prunedContents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Debounced entry point for periodic pruning. Called from `record(_:)`
    /// so retention is enforced as a side-effect of normal logging without
    /// spawning a background timer.
    private static func pruneOldEntriesIfNeeded() {
        pruneCheckLock.lock()
        let now = Date()
        if let last = lastPruneCheckAt, now.timeIntervalSince(last) < pruneDebounceInterval {
            pruneCheckLock.unlock()
            return
        }
        lastPruneCheckAt = now
        pruneCheckLock.unlock()

        pruneOldEntries(now: now)
    }

    /// Parses the leading ISO8601 timestamp of a log line. Returns `nil` for
    /// lines without a parseable timestamp (these are preserved).
    private static func timestamp(from line: String) -> Date? {
        guard let spaceIndex = line.firstIndex(of: " ") else {
            return nil
        }
        let prefix = String(line[..<spaceIndex])
        return timestampFormatter.date(from: prefix)
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
