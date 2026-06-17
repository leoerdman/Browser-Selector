import AppKit

final class BrowserTileButton: NSControl {
    var browserBundleIdentifier: String {
        browser.bundleIdentifier
    }

    var isDefaultChoice = false {
        didSet {
            updateAppearance()
        }
    }

    var isKeyboardSelected = false {
        didSet {
            updateAppearance()
        }
    }

    private let browser: Browser
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false

    init(browser: Browser, displayName: String? = nil) {
        self.browser = browser
        super.init(frame: .zero)
        setup()
        updateDisplayName(displayName ?? browser.shortDisplayName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isPressed = false
            updateAppearance()
        }

        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }

        sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        guard event.characters == " " || event.characters == "\r" else {
            super.keyDown(with: event)
            return
        }

        sendAction(action, to: target)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        setAccessibilityRole(.button)

        iconView.image = browser.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 46),
            iconView.heightAnchor.constraint(equalToConstant: 46),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8)
        ])

        updateAppearance()
    }

    func updateDisplayName(_ displayName: String) {
        nameLabel.stringValue = displayName
        toolTip = displayName == browser.displayName ? displayName : "\(displayName) (\(browser.displayName))"
        setAccessibilityLabel("Открыть в \(displayName)")
        setAccessibilityHelp("Открывает текущую ссылку в \(displayName).")
    }

    private func updateAppearance() {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let borderWidth: CGFloat

        if isPressed {
            backgroundColor = grayscaleTileFill(alpha: 0.26)
        } else if isHovering || isKeyboardSelected {
            backgroundColor = grayscaleTileFill(alpha: 0.18)
        } else if isDefaultChoice {
            backgroundColor = grayscaleTileFill(alpha: 0.12)
        } else {
            backgroundColor = .clear
        }

        if isDefaultChoice {
            borderColor = grayscaleTileBorder(alpha: 0.38)
            borderWidth = 1
        } else {
            borderColor = .clear
            borderWidth = 0
        }

        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderWidth
    }

    private func grayscaleTileFill(alpha: CGFloat) -> NSColor {
        let white: CGFloat = isDarkAppearance ? 1.0 : 0.0
        return NSColor(calibratedWhite: white, alpha: alpha)
    }

    private func grayscaleTileBorder(alpha: CGFloat) -> NSColor {
        let white: CGFloat = isDarkAppearance ? 1.0 : 0.0
        return NSColor(calibratedWhite: white, alpha: alpha)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
