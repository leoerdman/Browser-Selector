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

    func handle(url: URL) {
        DispatchQueue.main.async {
            self.pendingURLs.append(url)
            BrowserSelectorDiagnostics.record(
                "dispatch-enqueue \(BrowserSelectorDiagnostics.describe(url: url)) queueDepth=\(self.pendingURLs.count) hasActiveURL=\(self.activeURL != nil) hasActiveWindow=\(self.activeWindowController != nil)"
            )
            self.presentNextURLIfNeeded()
        }
    }

    private func presentNextURLIfNeeded() {
        guard activeURL == nil,
              activeWindowController == nil,
              !pendingURLs.isEmpty
        else {
            BrowserSelectorDiagnostics.record(
                "dispatch-present-skip activeURL=\(activeURL != nil) activeWindow=\(activeWindowController != nil) queueDepth=\(pendingURLs.count)"
            )
            return
        }

        let url = pendingURLs.removeFirst()
        activeURL = url
        BrowserSelectorDiagnostics.record(
            "dispatch-present-begin \(BrowserSelectorDiagnostics.describe(url: url)) remainingQueue=\(pendingURLs.count)"
        )

        let discoveredBrowsers = browserRepository.installedBrowsers()
        BrowserSelectorDiagnostics.record(
            "dispatch-discover-browsers count=\(discoveredBrowsers.count) ids=\(discoveredBrowsers.map(\.bundleIdentifier).joined(separator: ","))"
        )
        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: Set(discoveredBrowsers.map(\.bundleIdentifier))
        )
        guard !discoveredBrowsers.isEmpty else {
            BrowserSelectorDiagnostics.record("dispatch-no-browsers-found")
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
        BrowserSelectorDiagnostics.record(
            "dispatch-visible-browsers count=\(visibleDiscoveredBrowsers.count) hidden=\(discoveredBrowsers.count - visibleDiscoveredBrowsers.count)"
        )
        let preferredBundleIdentifier = preferences.rememberLastBrowser
            ? preferences.lastBrowserBundleIdentifier
            : nil
        let browsers = browserUsageStore.rankedBrowsers(
            visibleDiscoveredBrowsers,
            preferredBundleIdentifier: preferredBundleIdentifier
        )
        BrowserSelectorDiagnostics.record(
            "dispatch-ranked-browsers count=\(browsers.count) order=\(browsers.map(\.bundleIdentifier).joined(separator: ",")) preferred=\(preferredBundleIdentifier ?? "nil")"
        )
        guard !browsers.isEmpty else {
            BrowserSelectorDiagnostics.record("dispatch-no-visible-browsers")
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
        BrowserSelectorDiagnostics.record("dispatch-chooser-present")
        windowController.present()
    }

    private func handleChoiceResult(_ result: BrowserChoiceResult, for url: URL) {
        activeWindowController = nil

        switch result {
        case .cancel:
            BrowserSelectorDiagnostics.record("chooser-cancelled \(BrowserSelectorDiagnostics.describe(url: url))")
            finishActiveURL()

        case let .open(browser):
            BrowserSelectorDiagnostics.record(
                "chooser-opened \(BrowserSelectorDiagnostics.describe(url: url)) in \(browser.bundleIdentifier)"
            )
            preferences.rememberBrowserChoice(bundleIdentifier: browser.bundleIdentifier)

            browserLauncher.open(url, in: browser) { [weak self] openResult in
                DispatchQueue.main.async {
                    guard let self else {
                        BrowserSelectorDiagnostics.record("dispatch-launch-callback self=nil")
                        return
                    }

                    switch openResult {
                    case .success:
                        BrowserSelectorDiagnostics.record(
                            "launch-success \(BrowserSelectorDiagnostics.describe(url: url)) in \(browser.bundleIdentifier)"
                        )
                        self.recordBrowserUse(browser)
                        self.finishActiveURL()
                    case let .failure(error):
                        BrowserSelectorDiagnostics.record(
                            "launch-failure \(BrowserSelectorDiagnostics.describe(url: url)) in \(browser.bundleIdentifier) error=\(error.localizedDescription)"
                        )
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
        BrowserSelectorDiagnostics.record(
            "dispatch-finish activeURL=\(activeURL != nil) remainingQueue=\(pendingURLs.count)"
        )
        activeURL = nil
        presentNextURLIfNeeded()
    }
}
