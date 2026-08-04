import XCTest
@testable import BrowserSelector

final class BrowserSelectorDiagnosticsTests: XCTestCase {
    func testDescribeURLRedactsQueryValuesAndFragment() throws {
        let url = try XCTUnwrap(
            URL(string: "browser-selector://callback?code=secret-code&state=secret-state#id_token=secret-token")
        )

        XCTAssertEqual(
            BrowserSelectorDiagnostics.describe(url: url),
            "browser-selector://callback?code=redacted&state=redacted#redacted"
        )
    }

    func testDescribeURLKeepsURLsWithoutSecretsReadable() throws {
        let url = try XCTUnwrap(URL(string: "https://auth.openai.com/oauth/authorize"))

        XCTAssertEqual(
            BrowserSelectorDiagnostics.describe(url: url),
            "https://auth.openai.com/oauth/authorize"
        )
    }

    func testPruneOldEntriesRemovesLinesOlderThanRetentionInterval() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bs-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let logURL = tempDir.appendingPathComponent("diagnostics.log")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        let oldTimestamp = formatter.string(from: now.addingTimeInterval(-25 * 60 * 60))
        let freshTimestamp = formatter.string(from: now)
        let logContents = """
        \(oldTimestamp) old-line-should-be-pruned
        \(freshTimestamp) fresh-line-should-survive

        """
        try logContents.write(to: logURL, atomically: true, encoding: .utf8)

        BrowserSelectorDiagnostics.pruneOldEntries(at: logURL, now: now)

        let after = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(after.contains("old-line-should-be-pruned"))
        XCTAssertTrue(after.contains("fresh-line-should-survive"))
    }

    func testPruneOldEntriesIsNoOpWhenFileMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bs-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let missingLogURL = tempDir.appendingPathComponent("missing.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingLogURL.path))
        BrowserSelectorDiagnostics.pruneOldEntries(at: missingLogURL, now: Date())
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingLogURL.path))
    }

    func testRetentionIntervalIsTwentyFourHours() {
        XCTAssertEqual(BrowserSelectorDiagnostics.retentionInterval, 24 * 60 * 60)
    }
}
