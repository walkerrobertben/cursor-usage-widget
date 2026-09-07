#if canImport(AppKit)
import AppKit
import CursorUsageCore

/// AppKit dropdown over `MenuPresentation`.
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var presentation = MenuPresentation.make(from: UsageDisplayState())
    public var onRefreshRequested: (() -> Void)?
    public var onMenuWillOpen: (() -> Void)?
    public var onProfileSelected: ((String) -> Void)?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        updateStatusTitle()
    }

    public func apply(state: UsageDisplayState, calendar: DisplayCalendar = .current) {
        presentation = MenuPresentation.make(from: state, calendar: calendar)
        updateStatusTitle()
        statusItem.menu?.update()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        onMenuWillOpen?()
        rebuildMenu(menu)
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }

        switch presentation.menubar.kind {
        case let .warning(text):
            statusItem.isVisible = true
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = NSAttributedString(string: text, attributes: baseAttributes())
        case .hidden:
            button.attributedTitle = NSAttributedString(string: "")
            statusItem.isVisible = false
        case .loading:
            statusItem.isVisible = true
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = NSAttributedString(
                string: MenubarPresentation.loadingChip,
                attributes: baseAttributes()
            )
        case let .visible(segments):
            statusItem.isVisible = true
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = attributedTitle(from: segments)
        }
    }

    private func attributedTitle(from segments: [String]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for segment in segments {
            if title.length > 0 {
                title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
            }
            title.append(NSAttributedString(string: segment, attributes: baseAttributes()))
        }
        return title
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for row in presentation.rows {
            append(row, to: menu)
        }
    }

    private func append(_ row: MenuPresentation.Row, to menu: NSMenu) {
        switch row {
        case .separator:
            menu.addItem(.separator())
        case let .text(item):
            addInfoItem(
                to: menu,
                title: item.text,
                style: item.style,
                indentationLevel: item.indentation
            )
        case let .meter(item):
            addUsageMeter(to: menu, content: item.content)
        case let .model(content):
            let menuItem = NSMenuItem()
            menuItem.view = UsageModelRowView(content: content)
            menuItem.isEnabled = true
            menu.addItem(menuItem)
        case let .action(action):
            addAction(action, to: menu)
        case let .profileSwitcher(switcher):
            addProfileSwitcher(switcher, to: menu)
        }
    }

    private func addUsageMeter(to menu: NSMenu, content: UsageMeterContent) {
        let item = NSMenuItem()
        item.view = UsageMeterView(content: content)
        item.isEnabled = true
        menu.addItem(item)
    }

    private func addInfoItem(
        to menu: NSMenu,
        title: String,
        style: MenuPresentation.Style,
        indentationLevel: Int = 0
    ) {
        let item = NSMenuItem(title: "", action: #selector(ignoreMenuSelection), keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: infoItemAttributes(for: style)
        )
        item.target = self
        item.isEnabled = true
        item.indentationLevel = indentationLevel
        menu.addItem(item)
    }

    private func infoItemAttributes(for style: MenuPresentation.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .header, .section:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        case .body, .separator:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        case .secondary:
            return [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        }
    }

    private func addAction(_ action: MenuPresentation.ActionRow, to menu: NSMenu) {
        let selector: Selector
        switch action.role {
        case "refresh":
            selector = #selector(refreshNow)
        case "dashboard":
            selector = #selector(openDashboard)
        case "quit":
            selector = #selector(quit)
        default:
            selector = #selector(ignoreMenuSelection)
        }
        let item = NSMenuItem(
            title: action.title,
            action: selector,
            keyEquivalent: action.keyEquivalent ?? ""
        )
        item.target = self
        menu.addItem(item)
    }

    private func addProfileSwitcher(_ switcher: MenuPresentation.ProfileSwitcherRow, to menu: NSMenu) {
        let item = NSMenuItem(title: switcher.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for option in switcher.options {
            let optionItem = NSMenuItem(
                title: option.title,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            optionItem.target = self
            optionItem.state = option.isSelected ? .on : .off
            optionItem.representedObject = option.id
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func ignoreMenuSelection() {}

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onProfileSelected?(id)
    }

    @objc private func refreshNow() {
        onRefreshRequested?()
    }

    @objc private func openDashboard() {
        if let url = URL(string: AppInfo.dashboardURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif
