import AppKit
import XCTest
@testable import BrowserSelector

final class BrowserUsageStoreTests: XCTestCase {
    func testRecordUsePersistsSimpleTextCounts() throws {
        let fileURL = makeTemporaryFileURL()
        let store = BrowserUsageStore(fileURL: fileURL)

        try store.recordUse(bundleIdentifier: "com.google.Chrome")
        try store.recordUse(bundleIdentifier: "com.apple.Safari")
        try store.recordUse(bundleIdentifier: "com.google.Chrome")

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(
            contents,
            "com.apple.Safari\t1\ncom.google.Chrome\t2\n"
        )
    }

    func testRankedBrowsersMoveMostUsedBrowsersLeftAndKeepOriginalOrderForTies() throws {
        let fileURL = makeTemporaryFileURL()
        let store = BrowserUsageStore(fileURL: fileURL)
        try store.recordUse(bundleIdentifier: "org.mozilla.firefox")
        try store.recordUse(bundleIdentifier: "com.google.Chrome")
        try store.recordUse(bundleIdentifier: "com.google.Chrome")

        let safari = makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        let firefox = makeBrowser(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox")
        let chrome = makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Chrome")
        let rankedBrowsers = store.rankedBrowsers([safari, firefox, chrome])

        XCTAssertEqual(
            rankedBrowsers.map(\.bundleIdentifier),
            [
                "com.google.Chrome",
                "org.mozilla.firefox",
                "com.apple.Safari"
            ]
        )
    }

    func testRankedBrowsersIgnoreMalformedTextFileLines() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        malformed
        com.apple.Safari\tinvalid
        com.google.Chrome\t3
        org.mozilla.firefox\t0

        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = BrowserUsageStore(fileURL: fileURL)
        let safari = makeBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        let chrome = makeBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Chrome")

        XCTAssertEqual(store.usageCount(for: "com.apple.Safari"), 0)
        XCTAssertEqual(store.usageCount(for: "com.google.Chrome"), 3)
        XCTAssertEqual(store.rankedBrowsers([safari, chrome]).first?.bundleIdentifier, "com.google.Chrome")
    }

    func testRecordUseRejectsIdentifiersThatWouldBreakTheTextFileFormat() {
        let fileURL = makeTemporaryFileURL()
        let store = BrowserUsageStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.recordUse(bundleIdentifier: "com.example\tbad")) { error in
            XCTAssertTrue(error is BrowserUsageStoreError)
        }
    }

    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("browser-usage.txt", isDirectory: false)
    }

    private func makeBrowser(bundleIdentifier: String, displayName: String) -> Browser {
        Browser(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: URL(fileURLWithPath: "/Applications/\(displayName).app"),
            icon: NSImage(size: NSSize(width: 36, height: 36))
        )
    }
}
