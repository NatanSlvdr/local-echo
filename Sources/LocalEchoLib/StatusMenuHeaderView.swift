import AppKit

/// Shows the dictation state at the top of the status menu, like the headers of Control Center menus.
final class StatusMenuHeaderView: NSView {
    struct Content: Equatable {
        var symbol: String
        var tint: NSColor
        var title: String
        var detail: String
        /// A value from 0 to 100 shows a progress bar; nil hides it.
        var progress: Double?
    }

    private static let width: CGFloat = 300
    private static let insets = NSEdgeInsets(top: 6, left: 14, bottom: 8, right: 14)
    private static let badgeSize: CGFloat = 28

    private let badge = CircleBadgeView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let progressBar = NSProgressIndicator()
    private var content: Content?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 48))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        titleLabel.font = .boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3
        detailLabel.preferredMaxLayoutWidth = Self.width - Self.insets.left - Self.insets.right - Self.badgeSize - 10

        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100

        let text = NSStackView(views: [titleLabel, detailLabel, progressBar])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setCustomSpacing(6, after: detailLabel)

        let row = NSStackView(views: [badge, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.distribution = .fill
        // Let the text column take the remaining width so the progress bar spans the row.
        text.setHuggingPriority(.init(1), for: .horizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            badge.heightAnchor.constraint(equalToConstant: Self.badgeSize),
            progressBar.widthAnchor.constraint(equalTo: text.widthAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.insets.left),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.insets.right),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Self.insets.top),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.insets.bottom),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(_ content: Content) {
        guard content != self.content else { return }
        let sizeChanged = content.detail != self.content?.detail
            || (content.progress == nil) != (self.content?.progress == nil)
        self.content = content

        badge.tint = content.tint
        badge.symbol = content.symbol
        titleLabel.stringValue = content.title
        detailLabel.stringValue = content.detail
        detailLabel.isHidden = content.detail.isEmpty
        progressBar.isHidden = content.progress == nil
        progressBar.doubleValue = content.progress ?? 0
        setAccessibilityLabel([content.title, content.detail].filter { !$0.isEmpty }.joined(separator: ", "))

        if sizeChanged {
            let height = fittingSize.height
            setFrameSize(NSSize(width: max(frame.width, Self.width), height: height))
        }
    }
}

/// A filled circle with a white symbol, as used for Control Center toggles.
private final class CircleBadgeView: NSView {
    private let imageView = NSImageView()

    var tint: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    var symbol = "" {
        didSet {
            guard symbol != oldValue else { return }
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
    }

    init() {
        super.init(frame: .zero)
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        tint.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
