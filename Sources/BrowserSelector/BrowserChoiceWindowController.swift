import AppKit
import Foundation

enum BrowserChoiceResult {
    case open(browser: Browser, rememberSelection: Bool)
    case cancel
}

final class BrowserChoiceWindowController: NSWindowController {
    private enum Layout {
        static let windowWidth: CGFloat = 560
        static let horizontalPadding: CGFloat = 22
        static let verticalPadding: CGFloat = 18
        static let rowHeight: CGFloat = 54
        static let maxVisibleRows = 6
    }

    private let url: URL
    private let browsers: [Browser]
    private let preferences: Preferences
    private let completion: (BrowserChoiceResult) -> Void

    private let tableView = NSTableView()
    private let openButton = NSButton(title: "Открыть", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Отмена", target: nil, action: nil)
    private let rememberSelectionCheckbox = NSButton(
        checkboxWithTitle: "Запоминать выбранный браузер",
        target: nil,
        action: nil
    )

    private var didComplete = false

    init(
        url: URL,
        browsers: [Browser],
        preferences: Preferences,
        completion: @escaping (BrowserChoiceResult) -> Void
    ) {
        self.url = url
        self.browsers = browsers
        self.preferences = preferences
        self.completion = completion

        let visibleRows = max(1, min(browsers.count, Layout.maxVisibleRows))
        let windowHeight = CGFloat(visibleRows) * Layout.rowHeight + 178
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser Selector"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .transient]

        super.init(window: window)

        window.delegate = self
        buildInterface()
        selectInitialBrowser()
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
        rootView.material = .windowBackground
        rootView.blendingMode = .withinWindow
        rootView.state = .active
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let titleLabel = NSTextField(labelWithString: "Открыть ссылку через")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let urlLabel = NSTextField(wrappingLabelWithString: displayText(for: url))
        urlLabel.font = .systemFont(ofSize: 13, weight: .regular)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.maximumNumberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingMiddle

        let headerStack = NSStackView(views: [titleLabel, urlLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        configureTableView()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = browsers.count > Layout.maxVisibleRows
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        rememberSelectionCheckbox.state = preferences.rememberLastBrowser ? .on : .off
        rememberSelectionCheckbox.font = .systemFont(ofSize: 12)
        rememberSelectionCheckbox.target = self
        rememberSelectionCheckbox.action = #selector(rememberSelectionDidChange)

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"

        openButton.target = self
        openButton.action = #selector(openSelectedBrowser)
        openButton.keyEquivalent = "\r"
        openButton.bezelStyle = .rounded
        openButton.isEnabled = !browsers.isEmpty

        let footerButtons = NSStackView(views: [cancelButton, openButton])
        footerButtons.orientation = .horizontal
        footerButtons.alignment = .centerY
        footerButtons.spacing = 8

        let footerStack = NSStackView(views: [rememberSelectionCheckbox, NSView(), footerButtons])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 12
        footerStack.distribution = .fill
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [headerStack, scrollView, footerStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(rootStack)

        let visibleRows = max(1, min(browsers.count, Layout.maxVisibleRows))
        let tableHeight = CGFloat(visibleRows) * Layout.rowHeight

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Layout.horizontalPadding),
            rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Layout.horizontalPadding),
            rootStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Layout.verticalPadding),
            rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Layout.verticalPadding),

            headerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: tableHeight),
            footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        window.defaultButtonCell = openButton.cell as? NSButtonCell
    }

    private func configureTableView() {
        tableView.headerView = nil
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedBrowser)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular

        let column = NSTableColumn(identifier: BrowserCellView.reuseIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    private func selectInitialBrowser() {
        guard !browsers.isEmpty else {
            return
        }

        let selectedIndex: Int
        if preferences.rememberLastBrowser,
           let lastBrowserBundleIdentifier = preferences.lastBrowserBundleIdentifier,
           let index = browsers.firstIndex(where: { $0.bundleIdentifier == lastBrowserBundleIdentifier }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }

        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func displayText(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return "\(host)  ·  \(url.absoluteString)"
        }

        return url.absoluteString
    }

    @objc private func rememberSelectionDidChange() {
        preferences.rememberLastBrowser = rememberSelectionCheckbox.state == .on
    }

    @objc private func openSelectedBrowser() {
        let selectedRow = tableView.selectedRow
        guard browsers.indices.contains(selectedRow) else {
            return
        }

        complete(
            .open(
                browser: browsers[selectedRow],
                rememberSelection: rememberSelectionCheckbox.state == .on
            )
        )
    }

    @objc private func cancel() {
        complete(.cancel)
    }

    private func complete(_ result: BrowserChoiceResult) {
        guard !didComplete else {
            return
        }

        didComplete = true
        completion(result)
        close()
    }
}

extension BrowserChoiceWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        browsers.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Layout.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard browsers.indices.contains(row) else {
            return nil
        }

        let cell = tableView.makeView(
            withIdentifier: BrowserCellView.reuseIdentifier,
            owner: self
        ) as? BrowserCellView ?? BrowserCellView()

        cell.configure(with: browsers[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        openButton.isEnabled = tableView.selectedRow >= 0
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
