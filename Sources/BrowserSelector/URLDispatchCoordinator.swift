import AppKit
import Foundation

final class URLDispatchCoordinator {
    private let browserRepository: BrowserRepository
    private let browserLauncher: BrowserLauncher
    private let preferences: Preferences

    private var pendingURLs: [URL] = []
    private var activeWindowController: BrowserChoiceWindowController?
    private var activeURL: URL?

    init(
        browserRepository: BrowserRepository,
        browserLauncher: BrowserLauncher,
        preferences: Preferences
    ) {
        self.browserRepository = browserRepository
        self.browserLauncher = browserLauncher
        self.preferences = preferences
    }

    func handle(url: URL) {
        DispatchQueue.main.async {
            self.pendingURLs.append(url)
            self.presentNextURLIfNeeded()
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

        let browsers = browserRepository.installedBrowsers()
        guard !browsers.isEmpty else {
            finishActiveURL()
            UserNotifier.showError(
                title: "Браузеры не найдены",
                message: "LaunchServices не вернул ни одного приложения, которое умеет открывать web-ссылки."
            )
            return
        }

        let windowController = BrowserChoiceWindowController(
            url: url,
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
            finishActiveURL()

        case let .open(browser, rememberSelection):
            if rememberSelection {
                preferences.lastBrowserBundleIdentifier = browser.bundleIdentifier
            } else {
                preferences.lastBrowserBundleIdentifier = nil
            }

            browserLauncher.open(url, in: browser) { [weak self] openResult in
                DispatchQueue.main.async {
                    switch openResult {
                    case .success:
                        self?.finishActiveURL()
                    case let .failure(error):
                        self?.finishActiveURL()
                        UserNotifier.showError(
                            title: "Не удалось открыть ссылку",
                            message: "\(browser.displayName): \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
    }

    private func finishActiveURL() {
        activeURL = nil
        presentNextURLIfNeeded()
    }
}
