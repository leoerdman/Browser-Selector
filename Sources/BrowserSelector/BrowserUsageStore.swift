import Foundation

enum BrowserUsageStoreError: LocalizedError {
    case invalidBundleIdentifier(String)
    case counterOverflow(String)

    var errorDescription: String? {
        switch self {
        case let .invalidBundleIdentifier(bundleIdentifier):
            return "Некорректный bundle identifier для файла статистики: \(bundleIdentifier)"
        case let .counterOverflow(bundleIdentifier):
            return "Счетчик использования браузера переполнен: \(bundleIdentifier)"
        }
    }
}

final class BrowserUsageStore {
    static let shared = BrowserUsageStore(fileURL: defaultFileURL())

    private static let queueIdentityKey = DispatchSpecificKey<UUID>()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.leoerdman.BrowserSelector.browserUsageStore")
    private let queueIdentity = UUID()

    init(fileURL: URL) {
        self.fileURL = fileURL
        queue.setSpecific(key: Self.queueIdentityKey, value: queueIdentity)
    }

    func rankedBrowsers(
        _ browsers: [Browser],
        preferredBundleIdentifier: String? = nil
    ) -> [Browser] {
        let usageCounts = loadUsageCountsForRead()
        let originalIndices = Dictionary(
            uniqueKeysWithValues: browsers.enumerated().map { ($0.element.bundleIdentifier, $0.offset) }
        )

        return browsers.sorted { lhs, rhs in
            let lhsCount = usageCounts[lhs.bundleIdentifier] ?? 0
            let rhsCount = usageCounts[rhs.bundleIdentifier] ?? 0

            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }

            if let preferredBundleIdentifier,
               lhs.bundleIdentifier != rhs.bundleIdentifier,
               lhs.bundleIdentifier == preferredBundleIdentifier || rhs.bundleIdentifier == preferredBundleIdentifier {
                return lhs.bundleIdentifier == preferredBundleIdentifier
            }

            return (originalIndices[lhs.bundleIdentifier] ?? 0) < (originalIndices[rhs.bundleIdentifier] ?? 0)
        }
    }

    func recordUse(of browser: Browser) throws {
        try recordUse(bundleIdentifier: browser.bundleIdentifier)
    }

    func recordUse(bundleIdentifier: String) throws {
        try syncOnQueue {
            guard Self.isValidStorageKey(bundleIdentifier) else {
                throw BrowserUsageStoreError.invalidBundleIdentifier(bundleIdentifier)
            }

            var usageCounts = try loadUsageCounts()
            let currentCount = usageCounts[bundleIdentifier, default: 0]
            guard currentCount < Int.max else {
                throw BrowserUsageStoreError.counterOverflow(bundleIdentifier)
            }

            usageCounts[bundleIdentifier] = currentCount + 1
            try saveUsageCounts(usageCounts)
        }
    }

    func usageCount(for bundleIdentifier: String) -> Int {
        loadUsageCountsForRead()[bundleIdentifier] ?? 0
    }

    private func loadUsageCountsForRead() -> [String: Int] {
        do {
            return try syncOnQueue {
                try loadUsageCounts()
            }
        } catch {
            BrowserSelectorDiagnostics.record("usage-store-read-failed path=\(fileURL.path) error=\(error.localizedDescription)")
            return [:]
        }
    }

    private func syncOnQueue<T>(_ work: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: Self.queueIdentityKey) == queueIdentity {
            return try work()
        }

        return try queue.sync(execute: work)
    }

    private func loadUsageCounts() throws -> [String: Int] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let rawContents = try String(contentsOf: fileURL, encoding: .utf8)
        return rawContents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: Int]()) { usageCounts, line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count == 2,
                      let count = Int(columns[1]),
                      count > 0
                else {
                    return
                }

                let bundleIdentifier = String(columns[0])
                guard Self.isValidStorageKey(bundleIdentifier) else {
                    return
                }

                usageCounts[bundleIdentifier] = count
            }
    }

    private func saveUsageCounts(_ usageCounts: [String: Int]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let contents = usageCounts
            .filter { Self.isValidStorageKey($0.key) && $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            .map { "\($0.key)\t\($0.value)" }
            .joined(separator: "\n")

        let fileContents = contents.isEmpty ? "" : "\(contents)\n"
        try fileContents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func defaultFileURL() -> URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")

        return applicationSupportDirectory
            .appendingPathComponent("Browser Selector", isDirectory: true)
            .appendingPathComponent("browser-usage.txt", isDirectory: false)
    }

    private static func isValidStorageKey(_ value: String) -> Bool {
        !value.isEmpty && value.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) == nil
    }
}
