import Foundation

/// SSOT classifier for authentication-flow URLs that must bypass the browser
/// selection UI.
///
/// When a macOS application initiates `ASWebAuthenticationSession` (OAuth, OIDC,
/// SAML, SSO, device-code login), the resulting `claude.com/oauth/authorize`,
/// `accounts.google.com/o/oauth2/v2/auth`, `login.microsoftonline.com/...`,
/// etc. URLs land in Browser Selector via `application-open-urls`. If we
/// surface the browser-chooser for those URLs the user picks Chrome, Chrome
/// opens the OAuth provider's authorize page, and Claude's OAuth flow
/// collapses because the redirect target was never consumed by the originating
/// app. Worse, macOS re-prompts the same authorize URL an hour later when the
/// origin app retries, producing the "phantom browser chooser" bug.
///
/// `AuthFlowClassifier` is the single source of truth for deciding which
/// web URLs must be passed through to the system default browser without
/// showing the chooser.
enum AuthFlowClassifier {
    /// Path components (case-insensitive) that strongly indicate the URL is
    /// part of an OAuth/OIDC/SAML handshake rather than user-driven browsing.
    private static let authPathTokens: [String] = [
        "oauth",
        "oauth2",
        "oidc",
        "saml",
        "sso",
        "saml2",
        "signon",
        "sign-on",
        "sign_on",
        "authenticate",
        "authorize",
        "authorization",
        "callback",
        "redirect",
        "consent",
        "device",
        "device-code",
        "devicecode",
        "openid",
        "accounts.google.com",
        "login.microsoftonline.com",
        "login.live.com",
        "appleid.apple.com",
        "auth0.com",
        "okta.com",
        "okta",
        "auth",
        "authentication",
        "cai",
        "oauth-callback",
        "social-login",
        "social_login",
        "social-auth",
        "app-google-auth",
        "app-github-auth",
        "app-apple-auth",
        "app-microsoft-auth",
        "google-auth",
        "github-auth"
    ]

    /// Query parameters (case-insensitive) that confirm an OAuth/SSO flow.
    private static let authQueryKeys: Set<String> = [
        "code",
        "state",
        "client_id",
        "redirect_uri",
        "response_type",
        "scope",
        "id_token",
        "access_token",
        "refresh_token",
        "session_state",
        "openid",
        "nonce",
        "prompt",
        "acr_values"
    ]

    /// Host suffixes that host canonical OAuth/SSO providers and must always
    /// be passed through regardless of path.
    private static let authHostSuffixes: [String] = [
        "accounts.google.com",
        "login.microsoftonline.com",
        "login.live.com",
        "appleid.apple.com",
        "auth0.com",
        "okta.com",
        "oktapreview.com",
        "github.com",
        "gitlab.com",
        "slack.com",
        "linear.app",
        "notion.so",
        "claude.com"
    ]

    /// Returns `true` when the URL belongs to an authentication handshake
    /// and Browser Selector must NOT surface the chooser for it. The URL will
    /// be opened directly via `NSWorkspace.shared.open(_:)` so the system
    /// hands it to the OAuth provider's registered default handler.
    static func isAuthenticationFlow(_ url: URL) -> Bool {
        guard BrowserSelectorConstants.isWebURL(url) else {
            return false
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        if authHostSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        let path = url.path.lowercased()
        if !path.isEmpty, authPathTokens.contains(where: { path.contains("/" + $0 + "/") || path.hasPrefix("/" + $0) || path == "/" + $0 }) {
            return true
        }

        let pathComponents = path.split(separator: "/").map(String.init)
        if !pathComponents.isEmpty,
           authPathTokens.contains(where: { token in
               pathComponents.contains { component in
                   component == token || component.hasPrefix(token + "?")
               }
           })
        {
            return true
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           !queryItems.isEmpty
        {
            let keys = Set(queryItems.map { $0.name.lowercased() })
            if !keys.isDisjoint(with: authQueryKeys) {
                return true
            }
        }

        return false
    }
}
