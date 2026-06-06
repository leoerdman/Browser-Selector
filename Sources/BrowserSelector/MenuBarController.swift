import AppKit
import Foundation

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarControllerDidRequestDefaultRegistration(_ controller: MenuBarController)
    func menuBarControllerDidRequestBrowserRefresh(_ controller: MenuBarController)
    func menuBarControllerDidRequestTestOpen(_ controller: MenuBarController)
    func menuBarControllerDidRequestAbout(_ controller: MenuBarController)
}

final class MenuBarController: NSObject {
    private let registrationService: DefaultBrowserRegistrationService
    private let browserRepository: BrowserRepository
    private weak var delegate: MenuBarControllerDelegate?
    private var statusItem: NSStatusItem?

    init(
        registrationService: DefaultBrowserRegistrationService,
        browserRepository: BrowserRepository,
        delegate: MenuBarControllerDelegate
    ) {
        self.registrationService = registrationService
        self.browserRepository = browserRepository
        self.delegate = delegate
    }

    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIconFactory.makeStatusIcon()
        statusItem.button?.toolTip = "Browser Selector"
        self.statusItem = statusItem
        refreshMenu()
    }

    func refreshMenu() {
        let menu = NSMenu()
        let isDefaultBrowser = registrationService.isDefaultBrowser

        let titleItem = NSMenuItem(title: "Browser Selector", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusTitle = isDefaultBrowser
            ? "Активно: перехватывает ссылки"
            : "Не назначено браузером по умолчанию"
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

        addBrowserSummary(to: menu)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "О приложении", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
    }

    private func addBrowserSummary(to menu: NSMenu) {
        let browsers = browserRepository.installedBrowsers()
        let summaryItem = NSMenuItem(
            title: "Найдено браузеров: \(browsers.count)",
            action: nil,
            keyEquivalent: ""
        )
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)

        for browser in browsers.prefix(8) {
            let item = NSMenuItem(title: browser.displayName, action: nil, keyEquivalent: "")
            item.image = browser.icon
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func registerAsDefaultBrowser() {
        delegate?.menuBarControllerDidRequestDefaultRegistration(self)
    }

    @objc private func refreshBrowsers() {
        delegate?.menuBarControllerDidRequestBrowserRefresh(self)
    }

    @objc private func testOpen() {
        delegate?.menuBarControllerDidRequestTestOpen(self)
    }

    @objc private func showAbout() {
        delegate?.menuBarControllerDidRequestAbout(self)
    }
}
