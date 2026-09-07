#if canImport(AppKit)
import AppKit
import CursorUsageCore

enum UsageMenuMetrics {
    static let menuWidth: CGFloat = MenuLayout.menuWidth
    static let insetX: CGFloat = MenuLayout.insetX
    static let columnGap: CGFloat = MenuLayout.columnGap
    static let tokensColumnWidth: CGFloat = MenuLayout.tokensColumnWidth
    static let costColumnWidth: CGFloat = MenuLayout.costColumnWidth
    static let modelRowHeight: CGFloat = MenuLayout.modelRowHeight
}

/// Thin rounded usage bar plus captions, sized for an `NSMenuItem` custom view.
final class UsageMeterView: NSView {
    static let menuWidth: CGFloat = UsageMenuMetrics.menuWidth

    private enum Metrics {
        static let insetX: CGFloat = MenuLayout.insetX
        static let insetTop: CGFloat = MenuLayout.meterInsetTop
        static let insetBottom: CGFloat = MenuLayout.meterInsetBottom
        static let titleHeight: CGFloat = MenuLayout.meterTitleHeight
        static let subtitleHeight: CGFloat = MenuLayout.meterSubtitleHeight
        static let titleToSubtitle: CGFloat = MenuLayout.meterTitleToSubtitle
        static let titleToBar: CGFloat = MenuLayout.meterTitleToBar
        static let subtitleToBar: CGFloat = MenuLayout.meterSubtitleToBar
        static let barHeight: CGFloat = MenuLayout.meterBarHeight
        static let barToCaptions: CGFloat = MenuLayout.meterBarToCaptions
        static let captionHeight: CGFloat = MenuLayout.meterCaptionHeight
        static let captionGap: CGFloat = MenuLayout.meterCaptionGap
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
        switch UsageMeterLevel.from(percentUsed: percentUsed) {
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        }
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
#endif
