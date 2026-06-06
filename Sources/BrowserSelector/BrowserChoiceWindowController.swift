import AppKit
import Foundation

enum BrowserChoiceResult {
    case open(browser: Browser, rememberSelection: Bool)
    case cancel
}

final class BrowserChoiceWindowController: NSWindowController {
    private enum Layout {
        static let minWindowWidth: CGFloat = 360
        static let maxWindowWidth: CGFloat = 900
        static let horizontalPadding: CGFloat = 22
        static let verticalPadding: CGFloat = 16
        static let tileWidth: CGFloat = 112
        static let tileHeight: CGFloat = 108
        static let tileSpacing: CGFloat = 10
        static let windowHeight: CGFloat = 176
    }

    private let url: URL
    private let browsers: [Browser]
    private let preferences: Preferences
    private let completion: (BrowserChoiceResult) -> Void

    private let rememberSelectionCheckbox = NSButton(
        checkboxWithTitle: "Remember this choice",
        target: nil,
        action: nil
    )

    private var browserTileButtons: [BrowserTileButton] = []
    private var didComplete = false

    init(
        url: URL,
        browsers: [Browser],
        preferences: Preferences,
        completion: @escaping (BrowserChoiceResult) -> Void
    ) {
        self.url = url
        self.browsers = Self.orderedBrowsers(browsers, preferences: preferences)
        self.preferences = preferences
        self.completion = completion

        let window = BrowserChoiceWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.windowWidth(forBrowserCount: browsers.count),
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
        buildInterface()
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

        let rootView = NSVisualEffectView()
        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView
        rootView.menu = resetMenu()

        let browserStrip = makeBrowserStrip()

        rememberSelectionCheckbox.state = preferences.rememberLastBrowser ? .on : .off
        rememberSelectionCheckbox.font = .systemFont(ofSize: 12, weight: .regular)
        rememberSelectionCheckbox.target = self
        rememberSelectionCheckbox.action = #selector(rememberSelectionDidChange)

        let footerStack = NSStackView(views: [rememberSelectionCheckbox, NSView()])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 0
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [browserStrip, footerStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Layout.horizontalPadding),
            rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Layout.horizontalPadding),
            rootStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Layout.verticalPadding),
            rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Layout.verticalPadding),

            browserStrip.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            browserStrip.heightAnchor.constraint(equalToConstant: Layout.tileHeight),
            footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func makeBrowserStrip() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let viewportWidth = Self.windowWidth(forBrowserCount: browsers.count) - Layout.horizontalPadding * 2
        let browserContentWidth = browserStripContentWidth()
        let contentWidth = max(browserContentWidth, viewportWidth)
        scrollView.hasHorizontalScroller = browserContentWidth > viewportWidth

        let documentView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: contentWidth,
                height: Layout.tileHeight
            )
        )
        documentView.menu = resetMenu()

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = Layout.tileSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.menu = resetMenu()
        documentView.addSubview(stackView)

        let rememberedBrowserIdentifier = preferences.rememberLastBrowser
            ? preferences.lastBrowserBundleIdentifier
            : nil

        for (index, browser) in browsers.enumerated() {
            let button = BrowserTileButton(browser: browser)
            button.tag = index
            button.target = self
            button.action = #selector(browserTileDidClick(_:))
            button.isDefaultChoice = browser.bundleIdentifier == rememberedBrowserIdentifier
            button.menu = resetMenu()

            stackView.addArrangedSubview(button)
            browserTileButtons.append(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Layout.tileWidth),
                button.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
            ])
        }

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
        ])

        scrollView.documentView = documentView
        return scrollView
    }

    private func browserStripContentWidth() -> CGFloat {
        let browserCount = CGFloat(max(browsers.count, 1))
        return browserCount * Layout.tileWidth + max(0, browserCount - 1) * Layout.tileSpacing
    }

    @objc private func rememberSelectionDidChange() {
        preferences.rememberLastBrowser = rememberSelectionCheckbox.state == .on

        if rememberSelectionCheckbox.state == .off {
            preferences.lastBrowserBundleIdentifier = nil
            markRememberedBrowser(nil)
        }
    }

    @objc private func browserTileDidClick(_ sender: BrowserTileButton) {
        guard browsers.indices.contains(sender.tag) else {
            return
        }

        complete(
            .open(
                browser: browsers[sender.tag],
                rememberSelection: rememberSelectionCheckbox.state == .on
            )
        )
    }

    @objc private func resetRememberedChoice() {
        preferences.rememberLastBrowser = false
        preferences.lastBrowserBundleIdentifier = nil
        rememberSelectionCheckbox.state = .off
        markRememberedBrowser(nil)
    }

    private func resetMenu() -> NSMenu {
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

    private static func windowWidth(forBrowserCount browserCount: Int) -> CGFloat {
        let contentWidth = CGFloat(max(browserCount, 1)) * Layout.tileWidth
            + CGFloat(max(browserCount - 1, 0)) * Layout.tileSpacing
            + Layout.horizontalPadding * 2

        let screenLimit = NSScreen.main.map { $0.visibleFrame.width * 0.82 } ?? Layout.maxWindowWidth
        return min(max(contentWidth, Layout.minWindowWidth), min(Layout.maxWindowWidth, screenLimit))
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

private final class BrowserChoiceWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }
}
