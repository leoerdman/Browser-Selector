import AuthenticationServices
import Foundation

@available(macOS 10.15, *)
final class WebAuthenticationSessionCoordinator {
    init() {}

    /// Enterprise decision: Browser Selector does NOT intercept
    /// `ASWebAuthenticationSession` requests.
    ///
    /// OAuth flows (Google, Microsoft, Anthropic, etc.) launched by other
    /// applications require a full Safari instance because WKWebView cannot
    /// complete the OAuth dance (Google actively blocks embedded browsers,
    /// PKCE challenge/response needs real Safari storage, etc.).
    ///
    /// Previously we registered as
    /// `ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler`
    /// and intercepted every OAuth request from every app. When we cancelled
    /// the request (`cancelWithError`), macOS silently retained the session
    /// and re-activated it ~1 hour later, causing the browser-picker to
    /// re-appear out of context. This was reported as the top user-facing bug.
    ///
    /// By intentionally leaving `sessionHandler` unassigned, macOS opens the
    /// URL directly in the system's default auth browser (Safari), exactly as
    /// it does for every other application that is not a web-browser
    /// replacement. OAuth completes natively; the callback URL is delivered
    /// to the originating app (e.g. Claude, ChatGPT) via its registered URL
    /// scheme; no stray retries, no phantom picker.
    ///
    /// `wasLaunchedByAuthenticationServices` from the manager is inspected
    /// purely for diagnostics so we can see in logs when another app
    /// attempted an OAuth launch.
    @discardableResult
    func install() -> Bool {
        let manager = ASWebAuthenticationSessionWebBrowserSessionManager.shared
        let wasLaunchedByAuthenticationServices = manager.wasLaunchedByAuthenticationServices

        BrowserSelectorDiagnostics.record(
            "auth-session-handler disabled wasLaunchedByAuthenticationServices=\(wasLaunchedByAuthenticationServices)"
        )

        return false
    }
}
