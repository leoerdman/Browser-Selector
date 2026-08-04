import AuthenticationServices
import Foundation

@available(macOS 10.15, *)
final class WebAuthenticationSessionCoordinator {
    init() {}

    /// Enterprise decision: Browser Selector does NOT intercept
    /// `ASWebAuthenticationSession` requests as the system-role browser.
    ///
    /// Browser Selector intercepts every web link via LaunchServices (the
    /// `http`/`https` default handler) and surfaces a browser chooser; this
    /// includes OAuth/SSO URLs initiated by apps via
    /// `ASWebAuthenticationSession`. After the user picks a browser, the
    /// OAuth provider's authorize page opens in it, the user completes the
    /// consent flow, and macOS returns the registered callback URL to the
    /// originating application through that app's own registered URL
    /// scheme (e.g. `claude://`, `msauth.…://`, `chatgpt://`). This is the
    /// same callback path macOS uses for any non-default-browser app.
    ///
    /// By intentionally leaving
    /// `ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler`
    /// unassigned, the in-process WKWebView path is never taken. Earlier
    /// implementations registered a session handler and cancelled the
    /// request with `cancelWithError`, but macOS silently retained the
    /// session and re-activated it ~1 hour later, causing the browser
    /// picker to re-appear out of context.
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
