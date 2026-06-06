import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let browserRepository = BrowserRepository()
    private let browserLauncher = BrowserLauncher()
    private let registrationService = DefaultBrowserRegistrationService()

    private lazy var dispatchCoordinator = URLDispatchCoordinator(
        browserRepository: browserRepository,
        browserLauncher: browserLauncher,
        preferences: preferences
    )

    private lazy var menuBarController = MenuBarController(
        registrationService: registrationService,
        browserRepository: browserRepository,
        delegate: self
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        menuBarController.install()

        DispatchQueue.main.async { [weak self] in
            self?.showDefaultBrowserPromptIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { dispatchCoordinator.handle(url: $0) }
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else {
            UserNotifier.showError(
                title: "Не удалось прочитать ссылку",
                message: "macOS передала некорректный URL. Попробуйте открыть ссылку еще раз."
            )
            return
        }

        dispatchCoordinator.handle(url: url)
    }

    private func showDefaultBrowserPromptIfNeeded() {
        guard !registrationService.isDefaultBrowser else {
            menuBarController.refreshMenu()
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

        guard response == .alertFirstButtonReturn else {
            menuBarController.refreshMenu()
            return
        }

        registerAsDefaultBrowser()
    }

    private func registerAsDefaultBrowser() {
        do {
            try registrationService.registerAsDefaultBrowser()
            menuBarController.refreshMenu()

            if !registrationService.isDefaultBrowser {
                UserNotifier.showInfo(
                    title: "Подтвердите выбор в macOS",
                    message: "Если macOS показала системный запрос, подтвердите смену браузера по умолчанию. После этого все ссылки будут попадать в Browser Selector."
                )
            }
        } catch {
            menuBarController.refreshMenu()
            UserNotifier.showError(
                title: "Не удалось назначить браузер по умолчанию",
                message: error.localizedDescription
            )
        }
    }
}

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestDefaultRegistration(_ controller: MenuBarController) {
        registerAsDefaultBrowser()
    }

    func menuBarControllerDidRequestBrowserRefresh(_ controller: MenuBarController) {
        menuBarController.refreshMenu()
    }

    func menuBarControllerDidRequestTestOpen(_ controller: MenuBarController) {
        guard let url = URL(string: "https://example.com") else {
            return
        }

        dispatchCoordinator.handle(url: url)
    }

    func menuBarControllerDidRequestAbout(_ controller: MenuBarController) {
        UserNotifier.showInfo(
            title: "Browser Selector",
            message: "Нативная macOS-утилита для выбора браузера перед открытием ссылок.\n\nВерсия \(BrowserSelectorConstants.version)"
        )
    }
}
