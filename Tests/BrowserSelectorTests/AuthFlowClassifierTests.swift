import XCTest
@testable import BrowserSelector

final class AuthFlowClassifierTests: XCTestCase {
    func testOAuthCallbackIsAuthentication() {
        let url = URL(string: "https://claude.com/cai/oauth/authorize?code=abc")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testOIDCAuthorizeEndpointIsAuthentication() {
        let url = URL(string: "https://claude.com/oidc/authorize?client_id=x")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testSSOPathIsAuthentication() {
        let url = URL(string: "https://accounts.google.com/sso/start?next=app")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testLoginQueryParamIsAuthentication() {
        let url = URL(string: "https://example.com/?login=true&next=/dashboard")!
        XCTAssertFalse(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testCodeQueryParamIsAuthentication() {
        let url = URL(string: "https://example.com/?code=abc123")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testRegularURLIsNotAuthentication() {
        let url = URL(string: "https://example.com/articles/123")!
        XCTAssertFalse(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testLoginPageOnNonAuthHostIsNotAuthentication() {
        XCTAssertFalse(AuthFlowClassifier.isAuthenticationFlow(URL(string: "https://example.com/login")!))
        XCTAssertFalse(AuthFlowClassifier.isAuthenticationFlow(URL(string: "https://example.com/signin")!))
    }

    func testEmptyPathIsNotAuthentication() {
        XCTAssertFalse(AuthFlowClassifier.isAuthenticationFlow(URL(string: "https://example.com")!))
    }
}
