import XCTest
@testable import BrowserSelector

final class BrowserClassifierTests: XCTestCase {
    func testKnownBrowsersAreAcceptedAndKnownFalsePositiveIsDenied() {
        XCTAssertTrue(BrowserClassifier.isBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari"))
        XCTAssertTrue(BrowserClassifier.isBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome"))
        XCTAssertTrue(BrowserClassifier.isBrowser(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox"))
        XCTAssertTrue(BrowserClassifier.isBrowser(bundleIdentifier: "ai.perplexity.comet", displayName: "Comet"))

        XCTAssertFalse(
            BrowserClassifier.isBrowser(
                bundleIdentifier: "com.hegenberg.BetterTouchTool",
                displayName: "BetterTouchTool"
            )
        )
    }

    func testChromiumTabModelClassificationMatchesNewTabAutomationSupport() {
        XCTAssertTrue(BrowserClassifier.isChromiumLike(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(BrowserClassifier.isChromiumLike(bundleIdentifier: "com.google.Chrome.beta"))
        XCTAssertTrue(BrowserClassifier.isChromiumLike(bundleIdentifier: "ai.perplexity.comet"))

        XCTAssertFalse(BrowserClassifier.isChromiumLike(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(BrowserClassifier.isChromiumLike(bundleIdentifier: "org.mozilla.firefox"))
    }
}
