import AppKit
import Foundation

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarControllerDidRequestDefaultRegistration(_ controller: MenuBarController)
    func menuBarControllerDidRequestBrowserRefresh(_ controller: MenuBarController)
    func menuBarControllerDidRequestRememberedChoiceReset(_ controller: MenuBarController)
    func menuBarControllerDidRequestTestOpen(_ controller: MenuBarController)
    func menuBarControllerDidRequestAbout(_ controller: MenuBarController)
}

final class MenuBarController: NSObject {
    private let registrationService: DefaultBrowserRegistrationService
    private let browserRepository: BrowserRepository
    private let preferences: Preferences
    private weak var delegate: MenuBarControllerDelegate?
    private var statusItem: NSStatusItem?
    private var preferencesObserver: NSObjectProtocol?

    init(
        registrationService: DefaultBrowserRegistrationService,
        browserRepository: BrowserRepository,
        preferences: Preferences = .shared,
        delegate: MenuBarControllerDelegate
    ) {
        self.registrationService = registrationService
        self.browserRepository = browserRepository
        self.preferences = preferences
        self.delegate = delegate
    }

    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIconFactory.makeStatusIcon()
        statusItem.button?.toolTip = "Browser Selector"
        self.statusItem = statusItem
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .browserSelectorPreferencesDidChange,
            object: preferences,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMenu()
        }
        refreshMenu()
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
    }

    func refreshMenu() {
        let menu = NSMenu()
        let isDefaultBrowser = registrationService.isDefaultBrowser
        let browsers = browserRepository.installedBrowsers()
        preferences.reconcileRememberedBrowser(
            availableBundleIdentifiers: Set(browsers.map(\.bundleIdentifier))
        )

        let titleItem = NSMenuItem(title: "Browser Selector", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusTitle = isDefaultBrowser
            ? "Активен"
            : "Не назначен браузером по умолчанию"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let registerItem = NSMenuItem(
            title: "Назначить браузером по умолчанию",
            action: #selector(registerAsDefaultBrowser),
            keyEquivalent: ""
        )
        registerItem.target = self
        registerItem.isEnabled = !isDefaultBrowser
        menu.addItem(registerItem)

        menu.addItem(.separator())

        let rememberItem = NSMenuItem(
            title: "Запоминать выбранный браузер",
            action: #selector(toggleRememberBrowserChoice),
            keyEquivalent: ""
        )
        rememberItem.target = self
        rememberItem.state = preferences.rememberLastBrowser ? .on : .off
        menu.addItem(rememberItem)

        let rememberedItem = NSMenuItem(
            title: rememberedBrowserTitle(in: browsers),
            action: nil,
            keyEquivalent: ""
        )
        rememberedItem.isEnabled = false
        menu.addItem(rememberedItem)

        let resetItem = NSMenuItem(
            title: "Сбросить запомненный браузер",
            action: #selector(resetRememberedChoice),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.isEnabled = preferences.rememberLastBrowser || preferences.lastBrowserBundleIdentifier != nil
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(
            title: "Проверить окно выбора",
            action: #selector(testOpen),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        let refreshItem = NSMenuItem(
            title: "Обновить список браузеров",
            action: #selector(refreshBrowsers),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let browserCountItem = NSMenuItem(
            title: Self.browserCountTitle(browsers.count),
            action: nil,
            keyEquivalent: ""
        )
        browserCountItem.isEnabled = false
        menu.addItem(browserCountItem)

        addBrowserVisibilityItems(to: menu, browsers: browsers)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "О Browser Selector", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
    }

    @objc private func registerAsDefaultBrowser() {
        delegate?.menuBarControllerDidRequestDefaultRegistration(self)
    }

    @objc private func refreshBrowsers() {
        delegate?.menuBarControllerDidRequestBrowserRefresh(self)
    }

    @objc private func toggleRememberBrowserChoice() {
        if preferences.rememberLastBrowser {
            preferences.resetRememberedBrowserChoice()
        } else {
            preferences.rememberLastBrowser = true
        }

        refreshMenu()
    }

    @objc private func resetRememberedChoice() {
        delegate?.menuBarControllerDidRequestRememberedChoiceReset(self)
    }

    @objc private func testOpen() {
        delegate?.menuBarControllerDidRequestTestOpen(self)
    }

    @objc private func showAbout() {
        delegate?.menuBarControllerDidRequestAbout(self)
    }

    @objc private func toggleBrowserVisibility(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else {
            return
        }

        let shouldShow = !preferences.isBrowserVisible(bundleIdentifier: bundleIdentifier)
        guard shouldShow || canHideBrowser(bundleIdentifier: bundleIdentifier, browsers: browserRepository.installedBrowsers()) else {
            return
        }

        preferences.setBrowserVisibility(bundleIdentifier: bundleIdentifier, isVisible: shouldShow)
        refreshMenu()
    }

    private func addBrowserVisibilityItems(to menu: NSMenu, browsers: [Browser]) {
        guard !browsers.isEmpty else {
            return
        }

        let sectionTitle = NSMenuItem(title: "Показывать браузеры", action: nil, keyEquivalent: "")
        sectionTitle.isEnabled = false
        menu.addItem(sectionTitle)

        for browser in browsers {
            let item = NSMenuItem(
                title: browser.shortDisplayName,
                action: #selector(toggleBrowserVisibility(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = browser.bundleIdentifier
            item.state = preferences.isBrowserVisible(bundleIdentifier: browser.bundleIdentifier) ? .on : .off
            item.isEnabled = item.state == .off || canHideBrowser(
                bundleIdentifier: browser.bundleIdentifier,
                browsers: browsers
            )
            menu.addItem(item)
        }
    }

    private func rememberedBrowserTitle(in browsers: [Browser]) -> String {
        guard preferences.rememberLastBrowser else {
            return "Браузер по умолчанию: не запоминать"
        }

        guard let bundleIdentifier = preferences.lastBrowserBundleIdentifier else {
            return "Браузер по умолчанию: будет выбран после клика"
        }

        let browserName = browsers
            .first { $0.bundleIdentifier == bundleIdentifier }?
            .shortDisplayName

        return "Браузер по умолчанию: \(browserName ?? bundleIdentifier)"
    }

    private static func browserCountTitle(_ count: Int) -> String {
        let suffix: String
        let lastTwoDigits = count % 100
        let lastDigit = count % 10

        if (11...14).contains(lastTwoDigits) {
            suffix = "браузеров найдено"
        } else if lastDigit == 1 {
            suffix = "браузер найден"
        } else if (2...4).contains(lastDigit) {
            suffix = "браузера найдено"
        } else {
            suffix = "браузеров найдено"
        }

        return "\(count) \(suffix)"
    }

    private func canHideBrowser(bundleIdentifier: String, browsers: [Browser]) -> Bool {
        browsers.contains {
            $0.bundleIdentifier != bundleIdentifier
                && preferences.isBrowserVisible(bundleIdentifier: $0.bundleIdentifier)
        }
    }
}
