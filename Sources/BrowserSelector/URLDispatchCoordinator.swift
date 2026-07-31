import AppKit
import Foundation

final class URLDispatchCoordinator {
    private let browserRepository: BrowserRepository
    private let browserLauncher: BrowserLauncher
    private let browserUsageStore: BrowserUsageStore
    private let preferences: Preferences

    private var pendingURLs: [URL] = []

    var hasPendingURLs: Bool {
        !pendingURLs.isEmpty
    }
    private var activeWindowController: BrowserChoiceWindowController?
    private var activeURL: URL?
    private var authSessionCompletion: ((Bool) -> Void)?

    init(
        browserRepository: BrowserRepository,
        browserLauncher: BrowserLauncher,
        browserUsageStore: BrowserUsageStore,
        preferences: Preferences
    ) {
        self.browserRepository = browserRepository
        self.browserLauncher = browserLauncher
        self.browserUsageStore = browserUsageStore
        self.preferences = preferences
    }

    func handle(url: URL, authSessionCompletion: ((Bool) -> Void)? = nil) {
        self.authSessionCompletion = authSessionCompletion
        DispatchQueue.main.async {
            self.pendingURLs.append(url)
            self.presentNextURLIfNeeded()
        }
    }

    /// Opens the URL directly in the system default browser, bypassing the
    /// user-facing browser chooser. Used for OAuth/SSO callbacks that must
    /// flow through a single browser context to succeed.
    func handleAuthenticationPassthrough(url: URL) {
        BrowserSelectorDiagnostics.record("auth-passthrough \(BrowserSelectorDiagnostics.describe(url: url))")
        let didOpen = NSWorkspace.shared.open(url)
        if !didOpen {
            UserNotifier.showError(
                title: "Не удалось открыть auth-ссылку",
                message: "\(url.absoluteString)"
            )
        }
    }

    private func presentNextURLIfNeeded() {
        guard activeURL == nil,
              activeWindowController == nil,
              !pendingURLs.isEmpty
        else {
            return
        }

        let url = pendingURLs.removeFirst()
        activeURL = url

        let discoveredBrowsers = browserRepository.installedBrowsers()
        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: Set(discoveredBrowsers.map(\.bundleIdentifier))
        )
        guard !discoveredBrowsers.isEmpty else {
            UserNotifier.showError(
                title: "Браузеры не найдены",
                message: "LaunchServices не вернул ни одного приложения, которое умеет открывать web-ссылки."
            ) { [weak self] in
                self?.finishActiveURL()
            }
            return
        }

        let visibleDiscoveredBrowsers = discoveredBrowsers.filter {
            preferences.isBrowserVisible(bundleIdentifier: $0.bundleIdentifier)
        }
        let preferredBundleIdentifier = preferences.rememberLastBrowser
            ? preferences.lastBrowserBundleIdentifier
            : nil
        let browsers = browserUsageStore.rankedBrowsers(
            visibleDiscoveredBrowsers,
            preferredBundleIdentifier: preferredBundleIdentifier
        )
        guard !browsers.isEmpty else {
            UserNotifier.showError(
                title: "Нет видимых браузеров",
                message: "Все найденные браузеры скрыты. В menu bar включите хотя бы один браузер."
            ) { [weak self] in
                self?.finishActiveURL()
            }
            return
        }

        let windowController = BrowserChoiceWindowController(
            browsers: browsers,
            preferences: preferences
        ) { [weak self] result in
            self?.handleChoiceResult(result, for: url)
        }

        activeWindowController = windowController
        windowController.present()
    }

    private func handleChoiceResult(_ result: BrowserChoiceResult, for url: URL) {
        activeWindowController = nil

        switch result {
        case .cancel:
            authSessionCompletion?(false)
            authSessionCompletion = nil
            finishActiveURL()

        case let .open(browser):
            authSessionCompletion?(true)
            authSessionCompletion = nil
            preferences.rememberBrowserChoice(bundleIdentifier: browser.bundleIdentifier)

            browserLauncher.open(url, in: browser) { [weak self] openResult in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    switch openResult {
                    case .success:
                        self.recordBrowserUse(browser)
                        self.finishActiveURL()
                    case let .failure(error):
                        UserNotifier.showError(
                            title: "Не удалось открыть ссылку",
                            message: "\(browser.displayName(preferences: self.preferences)): \(error.localizedDescription)"
                        ) {
                            self.finishActiveURL()
                        }
                    }
                }
            }
        }
    }

    private func recordBrowserUse(_ browser: Browser) {
        do {
            try browserUsageStore.recordUse(of: browser)
        } catch {
            UserNotifier.showError(
                title: "Не удалось сохранить статистику браузера",
                message: "Ссылка открыта, но статистика использования \(browser.displayName(preferences: preferences)) не сохранена: \(error.localizedDescription)"
            )
        }
    }

    private func finishActiveURL() {
        activeURL = nil
        presentNextURLIfNeeded()
    }
}
