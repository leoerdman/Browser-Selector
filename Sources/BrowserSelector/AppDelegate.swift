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

    private lazy var menuBarController = MenuBarController(
        registrationService: registrationService,
        browserRepository: browserRepository,
        delegate: self
    )

    private var defaultBrowserMonitor: DispatchSourceTimer?
    private var defaultBrowserMonitorAttempts = 0

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

        guard !preferences.didShowDefaultBrowserPrompt else {
            menuBarController.refreshMenu()
            return
        }

        preferences.didShowDefaultBrowserPrompt = true

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
            let registrationState = try registrationService.requestDefaultBrowserRegistration()
            menuBarController.refreshMenu()

            switch registrationState {
            case .alreadyDefault:
                stopDefaultBrowserMonitor()
            case .requestedSystemConfirmation:
                startDefaultBrowserMonitor()
            }
        } catch {
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
        menuBarController.refreshMenu()

        if registrationService.isDefaultBrowser {
            stopDefaultBrowserMonitor()
            return
        }

        if defaultBrowserMonitorAttempts == 3 {
            do {
                _ = try registrationService.requestDefaultBrowserRegistration()
            } catch {
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

        stopDefaultBrowserMonitor()
        UserNotifier.showInfo(
            title: "Browser Selector не назначен",
            message: "macOS не применила смену браузера по умолчанию. В строке меню можно повторить назначение, если в системном окне был выбран текущий браузер."
        )
    }

    private func stopDefaultBrowserMonitor() {
        defaultBrowserMonitor?.cancel()
        defaultBrowserMonitor = nil
        defaultBrowserMonitorAttempts = 0
        menuBarController.refreshMenu()
    }
}

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestDefaultRegistration(_ controller: MenuBarController) {
        registerAsDefaultBrowser()
    }

    func menuBarControllerDidRequestBrowserRefresh(_ controller: MenuBarController) {
        menuBarController.refreshMenu()
    }

    func menuBarControllerDidRequestRememberedChoiceReset(_ controller: MenuBarController) {
        preferences.resetRememberedBrowserChoice()
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
            message: "Нативная macOS-утилита для выбора браузера перед открытием ссылок.\n\nВерсия \(AppMetadata.version)"
        )
    }
}
