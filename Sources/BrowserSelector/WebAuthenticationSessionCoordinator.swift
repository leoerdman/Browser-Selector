import AppKit
import AuthenticationServices
import Foundation
import WebKit

@available(macOS 10.15, *)
private func legacyCallbackURLScheme(for request: ASWebAuthenticationSessionRequest) -> String? {
    if #available(macOS 14.4, *) {
        return nil
    } else {
        return request.callbackURLScheme
    }
}

@available(macOS 10.15, *)
final class WebAuthenticationSessionCoordinator: NSObject {
    private var activeWindowControllers: [UUID: WebAuthenticationSessionWindowController] = [:]

    @discardableResult
    func install() -> Bool {
        let manager = ASWebAuthenticationSessionWebBrowserSessionManager.shared
        manager.sessionHandler = self
        let wasLaunchedByAuthenticationServices = manager.wasLaunchedByAuthenticationServices
        BrowserSelectorDiagnostics.record(
            "auth-session-handler installed wasLaunchedByAuthenticationServices=\(wasLaunchedByAuthenticationServices)"
        )
        return wasLaunchedByAuthenticationServices
    }

    private func beginHandling(_ request: ASWebAuthenticationSessionRequest) {
        BrowserSelectorDiagnostics.record(
            "auth-session begin uuid=\(request.uuid.uuidString) url=\(BrowserSelectorDiagnostics.describe(url: request.url)) ephemeral=\(request.shouldUseEphemeralSession) callback=\(Self.callbackDescription(for: request))"
        )
        let windowController = WebAuthenticationSessionWindowController(
            request: request
        ) { [weak self] requestIdentifier in
            self?.activeWindowControllers[requestIdentifier] = nil
        }

        activeWindowControllers[request.uuid]?.closeFromSystem()
        activeWindowControllers[request.uuid] = windowController
        windowController.present()
    }

    private func cancelHandling(_ request: ASWebAuthenticationSessionRequest) {
        BrowserSelectorDiagnostics.record("auth-session system-cancel uuid=\(request.uuid.uuidString)")
        activeWindowControllers[request.uuid]?.closeFromSystem()
        activeWindowControllers[request.uuid] = nil
    }

    private static func callbackDescription(for request: ASWebAuthenticationSessionRequest) -> String {
        if #available(macOS 14.4, *),
           request.callback != nil
        {
            return "modern"
        }

        guard let callbackURLScheme = legacyCallbackURLScheme(for: request),
              !callbackURLScheme.isEmpty
        else {
            return "none"
        }

        return "scheme:\(callbackURLScheme)"
    }
}

@available(macOS 10.15, *)
extension WebAuthenticationSessionCoordinator: ASWebAuthenticationSessionWebBrowserSessionHandling {
    func begin(_ request: ASWebAuthenticationSessionRequest!) {
        guard let request else {
            return
        }

        DispatchQueue.main.async {
            self.beginHandling(request)
        }
    }

    func cancel(_ request: ASWebAuthenticationSessionRequest!) {
        guard let request else {
            return
        }

        DispatchQueue.main.async {
            self.cancelHandling(request)
        }
    }
}

@available(macOS 10.15, *)
private final class WebAuthenticationSessionWindowController: NSWindowController {
    private enum Layout {
        static let initialWindowSize = NSSize(width: 1040, height: 760)
        static let minimumWindowSize = NSSize(width: 720, height: 520)
        static let toolbarHeight: CGFloat = 44
        static let controlSize = NSSize(width: 28, height: 28)
    }

    private let authenticationRequest: ASWebAuthenticationSessionRequest
    private let completion: (UUID) -> Void
    private let webView: WKWebView
    private let progressIndicator = NSProgressIndicator()
    private let hostLabel = NSTextField(labelWithString: "")
    private let reloadButton = NSButton()
    private let cancelButton = NSButton()
    private var didFinishSession = false

    init(
        request: ASWebAuthenticationSessionRequest,
        completion: @escaping (UUID) -> Void
    ) {
        self.authenticationRequest = request
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = request.shouldUseEphemeralSession
            ? .nonPersistent()
            : .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle(for: request.url, isEphemeral: request.shouldUseEphemeralSession)
        window.minSize = Layout.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func present() {
        guard let window else {
            return
        }

        loadInitialRequest()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeFromSystem() {
        finishSession {
            BrowserSelectorDiagnostics.record("auth-session close-from-system uuid=\(authenticationRequest.uuid.uuidString)")
            close()
        }
    }

    private func buildInterface() {
        guard let window else {
            return
        }

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let toolbarView = NSVisualEffectView()
        toolbarView.blendingMode = .withinWindow
        toolbarView.material = .headerView
        toolbarView.state = .active
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(toolbarView)

        hostLabel.stringValue = authenticationRequest.url.host ?? authenticationRequest.url.absoluteString
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(hostLabel)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(progressIndicator)

        reloadButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Reload"
        )
        reloadButton.bezelStyle = .texturedRounded
        reloadButton.target = self
        reloadButton.action = #selector(reloadPage)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(reloadButton)

        cancelButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Cancel"
        )
        cancelButton.bezelStyle = .texturedRounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelSessionFromButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(cancelButton)

        webView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: Layout.toolbarHeight),

            cancelButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: Layout.controlSize.width),
            cancelButton.heightAnchor.constraint(equalToConstant: Layout.controlSize.height),

            reloadButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            reloadButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: Layout.controlSize.width),
            reloadButton.heightAnchor.constraint(equalToConstant: Layout.controlSize.height),

            progressIndicator.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 12),
            progressIndicator.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 18),
            progressIndicator.heightAnchor.constraint(equalToConstant: 18),

            hostLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 10),
            hostLabel.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -12),
            hostLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),

            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func loadInitialRequest() {
        var urlRequest = URLRequest(url: authenticationRequest.url)
        if #available(macOS 14.4, *) {
            authenticationRequest.additionalHeaderFields?.forEach { field, value in
                urlRequest.setValue(value, forHTTPHeaderField: field)
            }
        }

        webView.load(urlRequest)
    }

    @objc private func reloadPage() {
        if webView.url == nil {
            loadInitialRequest()
        } else {
            webView.reload()
        }
    }

    @objc private func cancelSessionFromButton() {
        cancelSession()
    }

    private func cancelSession() {
        finishSession {
            BrowserSelectorDiagnostics.record("auth-session cancel uuid=\(authenticationRequest.uuid.uuidString)")
            authenticationRequest.cancelWithError(Self.cancelledLoginError())
            close()
        }
    }

    private func completeSession(with callbackURL: URL) {
        finishSession {
            BrowserSelectorDiagnostics.record(
                "auth-session complete uuid=\(authenticationRequest.uuid.uuidString) callback=\(BrowserSelectorDiagnostics.describe(url: callbackURL))"
            )
            authenticationRequest.complete(withCallbackURL: callbackURL)
            close()
        }
    }

    private func finishSession(_ action: () -> Void) {
        guard !didFinishSession else {
            return
        }

        didFinishSession = true
        webView.stopLoading()
        action()
        completion(authenticationRequest.uuid)
    }

    private func isCallbackURL(_ url: URL) -> Bool {
        if #available(macOS 14.4, *),
           let callback = authenticationRequest.callback
        {
            return callback.matchesURL(url)
        }

        guard let callbackURLScheme = legacyCallbackURLScheme(for: authenticationRequest),
              let urlScheme = url.scheme
        else {
            return false
        }

        return urlScheme.caseInsensitiveCompare(callbackURLScheme) == .orderedSame
    }

    private static func windowTitle(for url: URL, isEphemeral: Bool) -> String {
        let host = url.host ?? "Authentication"
        return isEphemeral ? "\(host) - Private Sign In" : "\(host) - Sign In"
    }

    private static func cancelledLoginError() -> NSError {
        NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.canceledLogin.rawValue
        )
    }
}

@available(macOS 10.15, *)
extension WebAuthenticationSessionWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame != false
        else {
            decisionHandler(.allow)
            return
        }

        if isCallbackURL(url) {
            BrowserSelectorDiagnostics.record(
                "auth-session callback-match uuid=\(authenticationRequest.uuid.uuidString) url=\(BrowserSelectorDiagnostics.describe(url: url))"
            )
            completeSession(with: url)
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased()
        if scheme != "http", scheme != "https", scheme != "about" {
            BrowserSelectorDiagnostics.record(
                "auth-session external-url uuid=\(authenticationRequest.uuid.uuidString) url=\(BrowserSelectorDiagnostics.describe(url: url))"
            )
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        hostLabel.stringValue = url.host ?? url.absoluteString
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progressIndicator.startAnimation(nil)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        progressIndicator.startAnimation(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressIndicator.stopAnimation(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        progressIndicator.stopAnimation(nil)
        recordNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        progressIndicator.stopAnimation(nil)
        recordNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        BrowserSelectorDiagnostics.record(
            "auth-session web-content-process-terminated uuid=\(authenticationRequest.uuid.uuidString)"
        )
        webView.reload()
    }

    private func recordNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else {
            return
        }

        let currentURL = webView.url.map(BrowserSelectorDiagnostics.describe(url:)) ?? "nil"
        BrowserSelectorDiagnostics.record(
            "auth-session navigation-failed uuid=\(authenticationRequest.uuid.uuidString) url=\(currentURL) error=\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
        )
    }
}

@available(macOS 10.15, *)
extension WebAuthenticationSessionWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        webView.load(navigationAction.request)
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        cancelSession()
    }
}

@available(macOS 10.15, *)
extension WebAuthenticationSessionWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        cancelSession()
    }
}
