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

        let titleItem = NSMenuItem(title: "Browser Selector", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusTitle = isDefaultBrowser
            ? "Active"
            : "Not Default Browser"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let registerItem = NSMenuItem(
            title: "Set as Default Browser",
            action: #selector(registerAsDefaultBrowser),
            keyEquivalent: ""
        )
        registerItem.target = self
        registerItem.isEnabled = !isDefaultBrowser
        menu.addItem(registerItem)

        menu.addItem(.separator())

        let rememberItem = NSMenuItem(
            title: "Remember Browser Choice",
            action: #selector(toggleRememberBrowserChoice),
            keyEquivalent: ""
        )
        rememberItem.target = self
        rememberItem.state = preferences.rememberLastBrowser ? .on : .off
        menu.addItem(rememberItem)

        let rememberedItem = NSMenuItem(
            title: rememberedBrowserTitle(),
            action: nil,
            keyEquivalent: ""
        )
        rememberedItem.isEnabled = false
        menu.addItem(rememberedItem)

        let resetItem = NSMenuItem(
            title: "Reset Remembered Choice",
            action: #selector(resetRememberedChoice),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.isEnabled = preferences.rememberLastBrowser || preferences.lastBrowserBundleIdentifier != nil
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(
            title: "Test Chooser",
            action: #selector(testOpen),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        let refreshItem = NSMenuItem(
            title: "Refresh Browsers",
            action: #selector(refreshBrowsers),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let browserCountItem = NSMenuItem(
            title: "\(browserRepository.installedBrowsers().count) Browsers Found",
            action: nil,
            keyEquivalent: ""
        )
        browserCountItem.isEnabled = false
        menu.addItem(browserCountItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Browser Selector", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    private func rememberedBrowserTitle() -> String {
        guard preferences.rememberLastBrowser else {
            return "Default Choice: Off"
        }

        guard let bundleIdentifier = preferences.lastBrowserBundleIdentifier else {
            return "Default Choice: Not Set"
        }

        let browserName = browserRepository.installedBrowsers()
            .first { $0.bundleIdentifier == bundleIdentifier }?
            .shortDisplayName

        return "Default Choice: \(browserName ?? bundleIdentifier)"
    }
}
