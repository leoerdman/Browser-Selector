import AppKit
import Foundation

enum BrowserChoiceResult {
    case open(browser: Browser, rememberSelection: Bool)
    case cancel
}

final class BrowserChoiceWindowController: NSWindowController {
    private enum Layout {
        static let minWindowWidth: CGFloat = 420
        static let maxWindowWidth: CGFloat = 920
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 18
        static let tileWidth: CGFloat = 104
        static let tileHeight: CGFloat = 104
        static let tileSpacing: CGFloat = 10
        static let windowHeight: CGFloat = 248
    }

    private let url: URL
    private let browsers: [Browser]
    private let preferences: Preferences
    private let completion: (BrowserChoiceResult) -> Void

    private let rememberSelectionCheckbox = NSButton(
        checkboxWithTitle: "Запомнить",
        target: nil,
        action: nil
    )
    private let defaultHintLabel = NSTextField(labelWithString: "")

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

        let window = NSWindow(
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

        let titleLabel = NSTextField(labelWithString: "Открыть через")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let urlLabel = NSTextField(labelWithString: displayText(for: url))
        urlLabel.font = .systemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.maximumNumberOfLines = 1

        let headerStack = NSStackView(views: [titleLabel, urlLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let browserStrip = makeBrowserStrip()

        rememberSelectionCheckbox.state = preferences.rememberLastBrowser ? .on : .off
        rememberSelectionCheckbox.font = .systemFont(ofSize: 11, weight: .regular)
        rememberSelectionCheckbox.target = self
        rememberSelectionCheckbox.action = #selector(rememberSelectionDidChange)

        defaultHintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        defaultHintLabel.textColor = .tertiaryLabelColor
        updateDefaultHint()

        let footerStack = NSStackView(views: [rememberSelectionCheckbox, defaultHintLabel, NSView()])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 8
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [headerStack, browserStrip, footerStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Layout.horizontalPadding),
            rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Layout.horizontalPadding),
            rootStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Layout.verticalPadding + 6),
            rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Layout.verticalPadding),

            headerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
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
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentWidth = browserStripContentWidth()
        let documentView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: contentWidth,
                height: Layout.tileHeight
            )
        )

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = Layout.tileSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
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

            stackView.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Layout.tileWidth),
                button.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
            ])
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.heightAnchor.constraint(equalToConstant: Layout.tileHeight)
        ])

        scrollView.documentView = documentView
        return scrollView
    }

    private func displayText(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return "\(host) · \(url.absoluteString)"
        }

        return url.absoluteString
    }

    private func browserStripContentWidth() -> CGFloat {
        let browserCount = CGFloat(max(browsers.count, 1))
        return browserCount * Layout.tileWidth + max(0, browserCount - 1) * Layout.tileSpacing
    }

    @objc private func rememberSelectionDidChange() {
        preferences.rememberLastBrowser = rememberSelectionCheckbox.state == .on

        if rememberSelectionCheckbox.state == .off {
            preferences.lastBrowserBundleIdentifier = nil
        }

        updateDefaultHint()
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

    private func updateDefaultHint() {
        defaultHintLabel.stringValue = rememberSelectionCheckbox.state == .on
            ? "следующий выбор станет браузером по умолчанию"
            : "по умолчанию: не запоминать"
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
