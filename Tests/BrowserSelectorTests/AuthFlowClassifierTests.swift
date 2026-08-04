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

    func testClaudeDotComOAuthAuthorizeIsAuthentication() {
        let url = URL(string: "https://claude.com/api/oauth/authorize?client_id=x&redirect_uri=y&response_type=code")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testGoogleAccountsOAuthIsAuthentication() {
        let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=x&redirect_uri=y&scope=openid")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }

    func testMicrosoftLoginAuthorizeIsAuthentication() {
        let url = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=x")!
        XCTAssertTrue(AuthFlowClassifier.isAuthenticationFlow(url))
    }
}
