import AppKit

final class BrowserCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("BrowserCellView")

    private let browserIconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let bundleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with browser: Browser) {
        browserIconView.image = browser.icon
        nameLabel.stringValue = browser.displayName
        bundleLabel.stringValue = browser.bundleIdentifier
    }

    private func setup() {
        wantsLayer = true

        browserIconView.translatesAutoresizingMaskIntoConstraints = false
        browserIconView.imageScaling = .scaleProportionallyUpOrDown
        browserIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        bundleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        bundleLabel.textColor = .secondaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        bundleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [nameLabel, bundleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(browserIconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            browserIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            browserIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            browserIconView.widthAnchor.constraint(equalToConstant: 36),
            browserIconView.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: browserIconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
