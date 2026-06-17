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
}
