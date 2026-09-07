#if canImport(AppKit)
import AppKit
import CursorUsageCore

/// Three-column model / tokens / cost row, aligned with `UsageMeterView`.
final class UsageModelRowView: NSView {
    private let content: UsageModelRowContent
    private let nameLabel = NSTextField(labelWithString: "")
    private let tokensLabel = NSTextField(labelWithString: "")
    private let costLabel = NSTextField(labelWithString: "")

    init(content: UsageModelRowContent) {
        self.content = content
        super.init(frame: .zero)
        autoresizingMask = [.width]
        configure()
        setFrameSize(NSSize(width: UsageMenuMetrics.menuWidth, height: UsageMenuMetrics.modelRowHeight))
        layoutSubtree()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: UsageMenuMetrics.menuWidth, height: UsageMenuMetrics.modelRowHeight)
    }

    override func layout() {
        super.layout()
        layoutSubtree()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func mouseDown(with event: NSEvent) {
        // Informational row; keep the menu open.
    }

    private func configure() {
        configureLabel(
            nameLabel,
            string: content.name,
            font: NSFont.systemFont(ofSize: 12, weight: .regular),
            alignment: .left
        )
        configureLabel(
            tokensLabel,
            string: content.tokens,
            font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            alignment: .right
        )
        configureLabel(
            costLabel,
            string: content.cost,
            font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            alignment: .right
        )

        addSubview(nameLabel)
        addSubview(tokensLabel)
        addSubview(costLabel)
        applyColors()

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(content.name), \(content.tokens), \(content.cost)")
    }

    private func configureLabel(
        _ label: NSTextField,
        string: String,
        font: NSFont,
        alignment: NSTextAlignment
    ) {
        label.stringValue = string
        label.font = font
        label.alignment = alignment
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
            nameLabel.textColor = .labelColor
            tokensLabel.textColor = .secondaryLabelColor
            costLabel.textColor = .labelColor
        }
    }

    private func layoutSubtree() {
        let inset = UsageMenuMetrics.insetX
        let gap = UsageMenuMetrics.columnGap
        let tokensWidth = UsageMenuMetrics.tokensColumnWidth
        let costWidth = UsageMenuMetrics.costColumnWidth
        let rowHeight = bounds.height

        let costX = bounds.width - inset - costWidth
        let tokensX = costX - gap - tokensWidth
        let nameWidth = max(0, tokensX - gap - inset)
        let labelHeight: CGFloat = 16
        let y = max(0, (rowHeight - labelHeight) / 2)

        nameLabel.frame = NSRect(x: inset, y: y, width: nameWidth, height: labelHeight)
        tokensLabel.frame = NSRect(x: tokensX, y: y, width: tokensWidth, height: labelHeight)
        costLabel.frame = NSRect(x: costX, y: y, width: costWidth, height: labelHeight)
    }
}
#endif
