import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let browserRepository = BrowserRepository()
    private let browserLauncher = BrowserLauncher()
    private let browserUsageStore = BrowserUsageStore.shared
    private let registrationService = DefaultBrowserRegistrationService()

    private lazy var dispatchCoordinator = URLDispatchCoordinator(
        browserRepository: browserRepository,
        browserLauncher: browserLauncher,
        browserUsageStore: browserUsageStore,
        preferences: preferences
    )

    private lazy var webAuthenticationSessionCoordinator = WebAuthenticationSessionCoordinator()

    private lazy var menuBarController = MenuBarController(
        registrationService: registrationService,
        browserRepository: browserRepository,
        delegate: self
    )

    private var defaultBrowserMonitor: DispatchSourceTimer?
    private var defaultBrowserMonitorAttempts = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        BrowserSelectorDiagnostics.record(
            "applicationWillFinishLaunching bundle=\(AppMetadata.bundleIdentifier ?? "nil")"
        )
        _ = webAuthenticationSessionCoordinator.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BrowserSelectorDiagnostics.record(
            "launch bundle=\(AppMetadata.bundleIdentifier ?? "nil") url=\(Bundle.main.bundleURL.path) version=\(AppMetadata.version)"
        )

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        BrowserSelectorDiagnostics.record("apple-event-handler registered for kAEGetURL")

        menuBarController.install()
        BrowserSelectorDiagnostics.record("menuBarController installed")

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                BrowserSelectorDiagnostics.record("launch self weaknil lost in didFinishLaunching dispatch")
                return
            }

            self.showDefaultBrowserPromptIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrowserSelectorDiagnostics.record("applicationWillTerminate")
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        BrowserSelectorDiagnostics.record(
            "application-open-urls \(urls.map(BrowserSelectorDiagnostics.describe(url:)).joined(separator: ", "))"
        )
        urls.forEach(routeIncomingURL)
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else {
            BrowserSelectorDiagnostics.record("apple-event-url invalid raw=\(event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "nil")")
            UserNotifier.showError(
                title: "Не удалось прочитать ссылку",
                message: "macOS передала некорректный URL. Попробуйте открыть ссылку еще раз."
            )
            return
        }

        BrowserSelectorDiagnostics.record("apple-event-url \(BrowserSelectorDiagnostics.describe(url: url))")
        routeIncomingURL(url)
    }

    private func routeIncomingURL(_ url: URL) {
        let isWeb = BrowserSelectorConstants.isWebURL(url)
        let isAuth = AuthFlowClassifier.isAuthenticationFlow(url)
        BrowserSelectorDiagnostics.record(
            "route-incoming \(BrowserSelectorDiagnostics.describe(url: url)) isWeb=\(isWeb) isAuth=\(isAuth)"
        )

        guard isWeb else {
            routeNonWebURL(url)
            return
        }

        if isAuth {
            BrowserSelectorDiagnostics.record(
                "auth-flow-detected chooser-open \(BrowserSelectorDiagnostics.describe(url: url))"
            )
        }

        dispatchCoordinator.handle(url: url)
    }

    private func routeNonWebURL(_ url: URL) {
        let targetApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        let targetBundleIdentifier = targetApplicationURL.flatMap { Bundle(url: $0)?.bundleIdentifier }

        guard targetBundleIdentifier != AppMetadata.bundleIdentifier else {
            BrowserSelectorDiagnostics.record("non-web-url blocked-self-loop \(BrowserSelectorDiagnostics.describe(url: url))")
            UserNotifier.showError(
                title: "Неподдерживаемая ссылка",
                message: "Browser Selector получил ссылку, которую macOS снова пытается открыть через Browser Selector: \(BrowserSelectorDiagnostics.describe(url: url))"
            )
            return
        }

        BrowserSelectorDiagnostics.record(
            "non-web-url passthrough \(BrowserSelectorDiagnostics.describe(url: url)) target=\(targetBundleIdentifier ?? "nil")"
        )
        let didOpen = NSWorkspace.shared.open(url)
        BrowserSelectorDiagnostics.record(
            "non-web-url open-result=\(didOpen) \(BrowserSelectorDiagnostics.describe(url: url))"
        )
    }

    private func showDefaultBrowserPromptIfNeeded() {
        let isDefault = registrationService.isDefaultBrowser
        BrowserSelectorDiagnostics.record(
            "default-browser-prompt isDefault=\(isDefault) didShowPrompt=\(preferences.didShowDefaultBrowserPrompt) hasPendingURLs=\(dispatchCoordinator.hasPendingURLs)"
        )

        guard !isDefault else {
            menuBarController.refreshMenu()
            return
        }

        guard !preferences.didShowDefaultBrowserPrompt else {
            menuBarController.refreshMenu()
            return
        }

        guard !dispatchCoordinator.hasPendingURLs else {
            BrowserSelectorDiagnostics.record("default-browser-prompt deferred due to pending URL dispatch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showDefaultBrowserPromptIfNeeded()
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Назначить Browser Selector браузером по умолчанию?"
        alert.informativeText = "Это нужно один раз, чтобы macOS отправляла ссылки в окно выбора браузера. После назначения приложение останется в строке меню."
        alert.addButton(withTitle: "Назначить")
        alert.addButton(withTitle: "Позже")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        BrowserSelectorDiagnostics.record("default-browser-prompt response=\(response.rawValue)")

        guard response == .alertFirstButtonReturn else {
            menuBarController.refreshMenu()
            return
        }

        preferences.didShowDefaultBrowserPrompt = true
        registerAsDefaultBrowser()
    }

    private func registerAsDefaultBrowser() {
        BrowserSelectorDiagnostics.record("registerAsDefaultBrowser begin")
        do {
            let registrationState = try registrationService.requestDefaultBrowserRegistration()
            BrowserSelectorDiagnostics.record("default-registration result=\(registrationState)")
            menuBarController.refreshMenu()

            switch registrationState {
            case .alreadyDefault:
                stopDefaultBrowserMonitor()
            case .requestedSystemConfirmation:
                startDefaultBrowserMonitor()
            }
        } catch {
            BrowserSelectorDiagnostics.record("default-registration error=\(error.localizedDescription)")
            menuBarController.refreshMenu()
            UserNotifier.showError(
                title: "Не удалось назначить браузер по умолчанию",
                message: error.localizedDescription
            )
        }
    }

    private func startDefaultBrowserMonitor() {
        stopDefaultBrowserMonitor()
        defaultBrowserMonitorAttempts = 0
        BrowserSelectorDiagnostics.record("default-browser-monitor start")

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.pollDefaultBrowserStatus()
        }
        defaultBrowserMonitor = timer
        timer.resume()
    }

    private func pollDefaultBrowserStatus() {
        defaultBrowserMonitorAttempts += 1
        let isDefault = registrationService.isDefaultBrowser
        BrowserSelectorDiagnostics.record(
            "default-browser-monitor attempt=\(defaultBrowserMonitorAttempts) isDefault=\(isDefault)"
        )
        menuBarController.refreshMenu()

        if isDefault {
            stopDefaultBrowserMonitor()
            return
        }

        if defaultBrowserMonitorAttempts == 3 {
            BrowserSelectorDiagnostics.record("default-browser-monitor retry registration at attempt=3")
            do {
                let retryState = try registrationService.requestDefaultBrowserRegistration()
                BrowserSelectorDiagnostics.record("default-browser-monitor retry result=\(retryState)")
            } catch {
                BrowserSelectorDiagnostics.record("default-browser-monitor retry error=\(error.localizedDescription)")
                stopDefaultBrowserMonitor()
                UserNotifier.showError(
                    title: "Не удалось завершить назначение",
                    message: error.localizedDescription
                )
            }
            return
        }

        guard defaultBrowserMonitorAttempts >= 20 else {
            return
        }

        BrowserSelectorDiagnostics.record("default-browser-monitor timeout after 20 attempts")
        stopDefaultBrowserMonitor()
        UserNotifier.showInfo(
            title: "Browser Selector не назначен",
            message: "macOS не применила смену браузера по умолчанию. В строке меню можно повторить назначение, если в системном окне был выбран текущий браузер."
        )
    }

    private func stopDefaultBrowserMonitor() {
        if defaultBrowserMonitor != nil {
            BrowserSelectorDiagnostics.record("default-browser-monitor stop")
        }
        defaultBrowserMonitor?.cancel()
        defaultBrowserMonitor = nil
        defaultBrowserMonitorAttempts = 0
        menuBarController.refreshMenu()
    }
}

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestDefaultRegistration(_ controller: MenuBarController) {
        BrowserSelectorDiagnostics.record("menu-action register-as-default requested")
        registerAsDefaultBrowser()
    }

    func menuBarControllerDidRequestBrowserRefresh(_ controller: MenuBarController) {
        BrowserSelectorDiagnostics.record("menu-action refresh-browsers requested")
        menuBarController.refreshMenu()
    }

    func menuBarControllerDidRequestRememberedChoiceReset(_ controller: MenuBarController) {
        BrowserSelectorDiagnostics.record("menu-action reset-remembered requested")
        preferences.resetRememberedBrowserChoice()
    }

    func menuBarControllerDidRequestTestOpen(_ controller: MenuBarController) {
        BrowserSelectorDiagnostics.record("menu-action test-open requested")
        guard let url = URL(string: "https://example.com") else {
            BrowserSelectorDiagnostics.record("menu-action test-open url-build-failed")
            return
        }

        dispatchCoordinator.handle(url: url)
    }

    func menuBarControllerDidRequestSystemLinkTest(_ controller: MenuBarController) {
        BrowserSelectorDiagnostics.record("menu-action system-link-test requested")
        guard let url = URL(string: "https://browser-selector.local/system-link-test") else {
            BrowserSelectorDiagnostics.record("menu-action system-link-test url-build-failed")
            return
        }

        BrowserSelectorDiagnostics.record("system-link-test \(BrowserSelectorDiagnostics.describe(url: url))")
        NSWorkspace.shared.open(url)
    }

    func menuBarControllerDidRequestDiagnostics(_ controller: MenuBarController) {
        let schemeHandlers = BrowserSelectorConstants.webURLSchemes.map { scheme in
            "\(scheme)=\(registrationService.defaultHandler(forURLScheme: scheme) ?? "nil")"
        }
        let contentTypeHandlers = BrowserSelectorConstants.webContentTypes.map { contentType in
            "\(contentType)=\(registrationService.defaultHandler(forContentType: contentType) ?? "nil")"
        }
        let recentLogLines = BrowserSelectorDiagnostics.recentLines(limit: 12)
        let messageParts = [
            "Bundle: \(AppMetadata.bundleIdentifier ?? "nil")",
            "App: \(Bundle.main.bundleURL.path)",
            "Handlers: \((schemeHandlers + contentTypeHandlers).joined(separator: ", "))",
            "Log: \(BrowserSelectorDiagnostics.logFileURL.path)",
            recentLogLines.isEmpty ? "Recent log: empty" : "Recent log:\n\(recentLogLines.joined(separator: "\n"))"
        ]

        UserNotifier.showInfo(
            title: "Browser Selector Diagnostics",
            message: messageParts.joined(separator: "\n\n")
        )
    }

    func menuBarControllerDidRequestAbout(_ controller: MenuBarController) {
        UserNotifier.showInfo(
            title: "Browser Selector",
            message: "Нативная macOS-утилита для выбора браузера перед открытием ссылок.\n\nВерсия \(AppMetadata.version)"
        )
    }
}
