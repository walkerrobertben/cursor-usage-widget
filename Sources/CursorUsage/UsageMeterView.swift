import AppKit

enum UsageMenuMetrics {
    static let menuWidth: CGFloat = 320
    static let insetX: CGFloat = 16
    static let columnGap: CGFloat = 10
    static let tokensColumnWidth: CGFloat = 80
    static let costColumnWidth: CGFloat = 56
    static let modelRowHeight: CGFloat = 20
}

struct UsageMeterContent {
    var title: String
    var subtitle: String?
    var percentUsed: Double
    var leftCaption: String
    var rightCaption: String
}

/// Thin rounded usage bar plus captions, sized for an `NSMenuItem` custom view.
final class UsageMeterView: NSView {
    static let menuWidth: CGFloat = UsageMenuMetrics.menuWidth

    private enum Metrics {
        static let insetX: CGFloat = UsageMenuMetrics.insetX
        static let insetTop: CGFloat = 8
        static let insetBottom: CGFloat = 8
        static let titleHeight: CGFloat = 16
        static let subtitleHeight: CGFloat = 14
        static let titleToSubtitle: CGFloat = 2
        static let titleToBar: CGFloat = 7
        static let subtitleToBar: CGFloat = 6
        static let barHeight: CGFloat = 5
        static let barToCaptions: CGFloat = 5
        static let captionHeight: CGFloat = 14
        static let captionGap: CGFloat = 8
    }

    private let content: UsageMeterContent
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let leftCaptionLabel = NSTextField(labelWithString: "")
    private let rightCaptionLabel = NSTextField(labelWithString: "")
    private let barView = UsageBarView()

    init(content: UsageMeterContent) {
        self.content = content
        super.init(frame: .zero)
        autoresizingMask = [.width]
        configure()
        setFrameSize(NSSize(width: Self.menuWidth, height: Self.height(for: content)))
        layoutSubtree()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.menuWidth, height: Self.height(for: content))
    }

    override func layout() {
        super.layout()
        layoutSubtree()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyColors()
        barView.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        barView.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Keep the menu open; the meter is informational, not an action.
    }

    static func height(for content: UsageMeterContent) -> CGFloat {
        var height = Metrics.insetTop + Metrics.titleHeight
        if showsSubtitle(content) {
            height += Metrics.titleToSubtitle + Metrics.subtitleHeight + Metrics.subtitleToBar
        } else {
            height += Metrics.titleToBar
        }
        height += Metrics.barHeight + Metrics.barToCaptions + Metrics.captionHeight + Metrics.insetBottom
        return height
    }

    private static func showsSubtitle(_ content: UsageMeterContent) -> Bool {
        guard let subtitle = content.subtitle else { return false }
        return !subtitle.isEmpty
    }

    private func configure() {
        wantsLayer = false

        configureLabel(
            titleLabel,
            string: content.title,
            font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        )
        configureLabel(
            subtitleLabel,
            string: content.subtitle ?? "",
            font: NSFont.systemFont(ofSize: 12, weight: .regular)
        )
        subtitleLabel.isHidden = !Self.showsSubtitle(content)

        configureLabel(
            leftCaptionLabel,
            string: content.leftCaption,
            font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        )
        configureLabel(
            rightCaptionLabel,
            string: content.rightCaption,
            font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        )
        rightCaptionLabel.alignment = .right
        rightCaptionLabel.isHidden = content.rightCaption.isEmpty

        barView.fraction = CGFloat(UsageFormatting.barFraction(percentUsed: content.percentUsed))
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(barView)
        addSubview(leftCaptionLabel)
        addSubview(rightCaptionLabel)

        applyColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilitySummary)
        barView.setAccessibilityElement(true)
        barView.setAccessibilityRole(.progressIndicator)
        barView.setAccessibilityLabel(content.title)
        barView.setAccessibilityValue(
            Int(min(max(content.percentUsed, 0), 100).rounded()) as NSNumber
        )
    }

    private var accessibilitySummary: String {
        var parts = [content.title]
        if let subtitle = content.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if !content.leftCaption.isEmpty {
            parts.append(content.leftCaption)
        }
        if !content.rightCaption.isEmpty {
            parts.append(content.rightCaption)
        }
        return parts.joined(separator: ", ")
    }

    private func configureLabel(_ label: NSTextField, string: String, font: NSFont) {
        label.stringValue = string
        label.font = font
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        label.refusesFirstResponder = true
        label.cell?.truncatesLastVisibleLine = true
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            titleLabel.textColor = .labelColor
            subtitleLabel.textColor = .secondaryLabelColor
            leftCaptionLabel.textColor = .secondaryLabelColor
            rightCaptionLabel.textColor = .secondaryLabelColor
            barView.fillColor = UsageMeterStyle.fillColor(percentUsed: content.percentUsed)
            barView.trackColor = NSColor.labelColor.withAlphaComponent(0.14)
        }
    }

    private func layoutSubtree() {
        let contentWidth = max(0, bounds.width - Metrics.insetX * 2)
        var y = Metrics.insetTop

        titleLabel.frame = NSRect(x: Metrics.insetX, y: y, width: contentWidth, height: Metrics.titleHeight)
        y += Metrics.titleHeight

        if !subtitleLabel.isHidden {
            y += Metrics.titleToSubtitle
            subtitleLabel.frame = NSRect(
                x: Metrics.insetX,
                y: y,
                width: contentWidth,
                height: Metrics.subtitleHeight
            )
            y += Metrics.subtitleHeight + Metrics.subtitleToBar
        } else {
            y += Metrics.titleToBar
        }

        barView.frame = NSRect(x: Metrics.insetX, y: y, width: contentWidth, height: Metrics.barHeight)
        y += Metrics.barHeight + Metrics.barToCaptions

        let captionSize = NSSize(width: contentWidth, height: Metrics.captionHeight)
        let leftWidth = min(
            leftCaptionLabel.sizeThatFits(captionSize).width,
            contentWidth
        )
        leftCaptionLabel.frame = NSRect(
            x: Metrics.insetX,
            y: y,
            width: leftWidth,
            height: Metrics.captionHeight
        )

        if !rightCaptionLabel.isHidden {
            let maxRightWidth = max(0, contentWidth - leftWidth - Metrics.captionGap)
            let rightWidth = min(
                rightCaptionLabel.sizeThatFits(captionSize).width,
                maxRightWidth
            )
            rightCaptionLabel.frame = NSRect(
                x: bounds.width - Metrics.insetX - rightWidth,
                y: y,
                width: rightWidth,
                height: Metrics.captionHeight
            )
        }
    }
}

enum UsageMeterStyle {
    static func fillColor(percentUsed: Double) -> NSColor {
        if percentUsed >= 100 {
            return .systemRed
        }
        if percentUsed >= 90 {
            return .systemOrange
        }
        if percentUsed >= 70 {
            return .systemYellow
        }
        return .systemGreen
    }
}

final class UsageBarView: NSView {
    var fraction: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    var trackColor: NSColor = NSColor.labelColor.withAlphaComponent(0.14) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let rect = bounds
            let radius = rect.height / 2

            trackColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

            let clamped = min(max(fraction, 0), 1)
            guard clamped > 0 else { return }

            var fillWidth = rect.width * clamped
            fillWidth = max(fillWidth, rect.height)
            fillWidth = min(fillWidth, rect.width)

            fillColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height),
                xRadius: radius,
                yRadius: radius
            ).fill()
        }
    }
}
