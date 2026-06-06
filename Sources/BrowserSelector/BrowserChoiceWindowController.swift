import AppKit
import Foundation

enum BrowserChoiceResult {
    case open(browser: Browser)
    case cancel
}

final class BrowserChoiceWindowController: NSWindowController {
    private enum Layout {
        static let outerPadding: CGFloat = 12
        static let preferredTileWidth: CGFloat = 108
        static let minimumTileWidth: CGFloat = 64
        static let tileHeight: CGFloat = 96
        static let tileSpacing: CGFloat = 8
        static let maxScreenWidthFraction: CGFloat = 0.94

        static var windowHeight: CGFloat {
            tileHeight + outerPadding * 2
        }
    }

    private let browsers: [Browser]
    private let preferences: Preferences
    private let completion: (BrowserChoiceResult) -> Void
    private let tileWidth: CGFloat

    private var browserTileButtons: [BrowserTileButton] = []
    private lazy var contextMenu = makeResetMenu()
    private var selectedIndex: Int
    private var didComplete = false

    init(
        browsers: [Browser],
        preferences: Preferences,
        completion: @escaping (BrowserChoiceResult) -> Void
    ) {
        let orderedBrowsers = Self.orderedBrowsers(browsers, preferences: preferences)
        let windowMetrics = Self.windowMetrics(forBrowserCount: orderedBrowsers.count)
        self.browsers = orderedBrowsers
        self.preferences = preferences
        self.completion = completion
        self.tileWidth = windowMetrics.tileWidth
        self.selectedIndex = Self.initialSelectedIndex(in: orderedBrowsers, preferences: preferences)

        let window = BrowserChoiceWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: windowMetrics.windowWidth,
                height: Layout.windowHeight
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser Selector"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .transient]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        window.delegate = self
        window.onCancel = { [weak self] in
            self?.complete(.cancel)
        }
        window.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        buildInterface()
        updateTileSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        guard let window else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface() {
        guard let window else {
            return
        }

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView
        rootView.menu = contextMenu

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(backgroundView)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.menu = contextMenu
        rootView.addSubview(contentView)

        let browserStrip = makeBrowserStrip()

        let rootStack = NSStackView(views: [browserStrip])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.outerPadding),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.outerPadding),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.outerPadding),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.outerPadding),

            browserStrip.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            browserStrip.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
        ])
    }

    private func makeBrowserStrip() -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.menu = contextMenu

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = Layout.tileSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.menu = contextMenu
        containerView.addSubview(stackView)

        let rememberedBrowserIdentifier = preferences.rememberLastBrowser
            ? preferences.lastBrowserBundleIdentifier
            : nil

        for (index, browser) in browsers.enumerated() {
            let button = BrowserTileButton(browser: browser)
            button.tag = index
            button.target = self
            button.action = #selector(browserTileDidClick(_:))
            button.isDefaultChoice = browser.bundleIdentifier == rememberedBrowserIdentifier
            button.menu = contextMenu

            stackView.addArrangedSubview(button)
            browserTileButtons.append(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: tileWidth),
                button.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
            ])
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
        ])

        return containerView
    }

    @objc private func browserTileDidClick(_ sender: BrowserTileButton) {
        guard browsers.indices.contains(sender.tag) else {
            return
        }

        selectedIndex = sender.tag
        updateTileSelection()
        complete(
            .open(browser: browsers[sender.tag])
        )
    }

    @objc private func resetRememberedChoice() {
        preferences.resetRememberedBrowserChoice()
        markRememberedBrowser(nil)
    }

    private func makeResetMenu() -> NSMenu {
        let menu = NSMenu()
        let resetItem = NSMenuItem(
            title: "Reset remembered choice",
            action: #selector(resetRememberedChoice),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)
        return menu
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            moveSelection(by: -1)
            return true
        case 124:
            moveSelection(by: 1)
            return true
        case 36, 49, 76:
            openSelectedBrowser()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !browsers.isEmpty else {
            return
        }

        selectedIndex = (selectedIndex + delta + browsers.count) % browsers.count
        updateTileSelection()
    }

    private func openSelectedBrowser() {
        guard browsers.indices.contains(selectedIndex) else {
            return
        }

        complete(
            .open(browser: browsers[selectedIndex])
        )
    }

    private func updateTileSelection() {
        for (index, button) in browserTileButtons.enumerated() {
            button.isKeyboardSelected = index == selectedIndex
        }
    }

    private func markRememberedBrowser(_ bundleIdentifier: String?) {
        for button in browserTileButtons {
            button.isDefaultChoice = button.browserBundleIdentifier == bundleIdentifier
        }
    }

    private func complete(_ result: BrowserChoiceResult) {
        guard !didComplete else {
            return
        }

        didComplete = true
        completion(result)
        close()
    }

    private static func orderedBrowsers(_ browsers: [Browser], preferences: Preferences) -> [Browser] {
        guard preferences.rememberLastBrowser,
              let lastBrowserBundleIdentifier = preferences.lastBrowserBundleIdentifier,
              let rememberedBrowser = browsers.first(where: { $0.bundleIdentifier == lastBrowserBundleIdentifier })
        else {
            return browsers
        }

        return [rememberedBrowser] + browsers.filter { $0.bundleIdentifier != lastBrowserBundleIdentifier }
    }

    private static func initialSelectedIndex(in browsers: [Browser], preferences: Preferences) -> Int {
        guard preferences.rememberLastBrowser,
              let lastBrowserBundleIdentifier = preferences.lastBrowserBundleIdentifier,
              let index = browsers.firstIndex(where: { $0.bundleIdentifier == lastBrowserBundleIdentifier })
        else {
            return 0
        }

        return index
    }

    private static func windowMetrics(forBrowserCount browserCount: Int) -> (windowWidth: CGFloat, tileWidth: CGFloat) {
        let count = CGFloat(max(browserCount, 1))
        let screenLimit = NSScreen.main.map { $0.visibleFrame.width * Layout.maxScreenWidthFraction } ?? 900
        let availableTileWidth = floor(
            (screenLimit - Layout.outerPadding * 2 - max(0, count - 1) * Layout.tileSpacing) / count
        )
        let tileWidth = min(Layout.preferredTileWidth, max(Layout.minimumTileWidth, availableTileWidth))
        let contentWidth = count * tileWidth + max(0, count - 1) * Layout.tileSpacing
        let windowWidth = contentWidth + Layout.outerPadding * 2

        return (windowWidth, tileWidth)
    }
}

extension BrowserChoiceWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !didComplete else {
            return
        }

        didComplete = true
        completion(.cancel)
    }
}

extension BrowserChoiceWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(resetRememberedChoice) else {
            return true
        }

        return preferences.rememberLastBrowser || preferences.lastBrowserBundleIdentifier != nil
    }
}

private final class BrowserChoiceWindow: NSWindow {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if onKeyDown?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
