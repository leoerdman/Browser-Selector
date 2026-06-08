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
    private var outsideClickMonitor: OutsidePanelClickMonitor?

    init(
        browsers: [Browser],
        preferences: Preferences,
        completion: @escaping (BrowserChoiceResult) -> Void
    ) {
        let windowMetrics = Self.windowMetrics(forBrowserCount: browsers.count)
        self.browsers = browsers
        self.preferences = preferences
        self.completion = completion
        self.tileWidth = windowMetrics.tileWidth
        self.selectedIndex = 0

        let window = BrowserChoiceWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: windowMetrics.windowWidth,
                height: Layout.windowHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser Selector"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .transient]

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

    deinit {
        stopOutsideClickMonitor()
    }

    func present() {
        guard let window else {
            return
        }

        window.center()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startOutsideClickMonitor()
    }

    func cancelIfMouseDownIsOutsidePanel(at screenLocation: NSPoint) {
        guard let window,
              !window.frame.contains(screenLocation)
        else {
            return
        }

        complete(.cancel)
    }

    private func buildInterface() {
        guard let window else {
            return
        }

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView
        rootView.menu = contextMenu

        let backgroundView = GrayscalePanelBackgroundView()
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
        stopOutsideClickMonitor()
        completion(result)
        close()
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        let monitor = OutsidePanelClickMonitor { [weak self] screenLocation in
            self?.cancelIfMouseDownIsOutsidePanel(at: screenLocation)
        }
        monitor.start()
        outsideClickMonitor = monitor
    }

    private func stopOutsideClickMonitor() {
        outsideClickMonitor?.stop()
        outsideClickMonitor = nil
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

        stopOutsideClickMonitor()
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

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        if event.isEscapeKey {
            onCancel?()
            return
        }

        if onKeyDown?(event) == true {
            return
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.isEscapeKey {
            onCancel?()
            return
        }

        if onKeyDown?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

private extension NSEvent {
    var isEscapeKey: Bool {
        keyCode == 53 || charactersIgnoringModifiers == "\u{1B}"
    }
}

private final class OutsidePanelClickMonitor {
    private static let mouseDownEvents: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    private let onMouseDown: (NSPoint) -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(onMouseDown: @escaping (NSPoint) -> Void) {
        self.onMouseDown = onMouseDown
    }

    deinit {
        stop()
    }

    func start() {
        guard localMonitor == nil,
              globalMonitor == nil
        else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mouseDownEvents) { [weak self] event in
            self?.handle(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mouseDownEvents) { [weak self] event in
            let screenLocation = Self.screenLocation(for: event)
            DispatchQueue.main.async {
                self?.onMouseDown(screenLocation)
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        onMouseDown(Self.screenLocation(for: event))
    }

    private static func screenLocation(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }

        return NSEvent.mouseLocation
    }
}

private final class GrayscalePanelBackgroundView: NSView {
    private enum Palette {
        static let darkBackground = NSColor(calibratedWhite: 0.20, alpha: 0.70)
        static let lightBackground = NSColor(calibratedWhite: 0.88, alpha: 0.70)
        static let darkBorder = NSColor(calibratedWhite: 1.00, alpha: 0.16)
        static let lightBorder = NSColor(calibratedWhite: 0.00, alpha: 0.18)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (isDark ? Palette.darkBackground : Palette.lightBackground).cgColor
        layer?.borderColor = (isDark ? Palette.darkBorder : Palette.lightBorder).cgColor
    }
}
