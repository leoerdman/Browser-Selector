import XCTest
@testable import BrowserSelector

final class BrowserLaunchScriptFactoryTests: XCTestCase {
    func testAppleScriptLiteralEscapesValuesWithoutChangingURLContent() {
        let value = #"https://example.com/search?q="quoted"\path&next=https%3A%2F%2Fexample.com%2F"#

        XCTAssertEqual(
            BrowserLaunchScriptFactory.appleScriptLiteral(value),
            #""https://example.com/search?q=\"quoted\"\\path&next=https%3A%2F%2Fexample.com%2F""#
        )
    }

    func testOpenLocationScriptPreservesCommonHTTPAndHTTPSLinkForms() {
        let urlStrings = [
            "https://example.com",
            "http://example.com/path?x=1&y=two#section",
            "https://localhost:3000/callback?next=https%3A%2F%2Fexample.com%2Fdone",
            "http://127.0.0.1:8080/a/b?debug=true",
            "https://xn--e1afmkfd.xn--p1ai/%D0%BF%D1%83%D1%82%D1%8C?key=%D0%B7%D0%BD%D0%B0%D1%87%D0%B5%D0%BD%D0%B8%D0%B5",
            "https://example.com/search?q=%22quoted%20value%22&slash=%5C"
        ]

        for urlString in urlStrings {
            let script = BrowserLaunchScriptFactory.openLocationScript(
                bundleIdentifier: "com.apple.Safari",
                urlString: urlString
            )

            XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
            XCTAssertTrue(script.contains("open location \(BrowserLaunchScriptFactory.appleScriptLiteral(urlString))"))
        }
    }

    func testChromiumScriptTargetsTheFrontWindowAndCreatesANewActiveTab() {
        let script = BrowserLaunchScriptFactory.chromiumNewTabScript(
            bundleIdentifier: "com.google.Chrome",
            urlString: "https://example.com/path?x=1#fragment"
        )

        XCTAssertTrue(script.contains("tell application id \"com.google.Chrome\""))
        XCTAssertTrue(script.contains("if (count of windows) = 0 then make new window"))
        XCTAssertTrue(script.contains("tell front window"))
        XCTAssertTrue(script.contains("make new tab at end of tabs"))
        XCTAssertTrue(script.contains("set active tab index to (count of tabs)"))
        XCTAssertTrue(script.contains(#"URL:"https://example.com/path?x=1#fragment""#))
    }
}
