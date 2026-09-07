import Foundation
import CursorUsageCore

/// Idempotent HTML view of `MenuPresentation`.
public enum MenuHTMLRenderer {
    public enum Appearance: String, Sendable {
        case light
        case dark
    }

    public static func document(
        _ presentation: MenuPresentation,
        appearance: Appearance = .light,
        title: String = "Cursor Usage"
    ) -> String {
        let menubar = menubarChip(presentation.menubar)
        let rows = presentation.rows.map { renderRow($0) }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en" data-appearance="\(appearance.rawValue)">
        <head>
          <meta charset="utf-8">
          <title>\(escape(title))</title>
          <style>
            \(css(appearance))
          </style>
        </head>
        <body>
          <div class="stage">
            \(menubar)
            <div class="menu" role="menu" aria-label="\(escape(title))">
              \(rows)
            </div>
          </div>
        </body>
        </html>
        """
    }

    private static func menubarChip(_ menubar: MenuPresentation.Menubar) -> String {
        switch menubar.kind {
        case .hidden:
            return #"<div class="menubar hidden">(hidden)</div>"#
        case let .warning(text):
            return #"<div class="menubar warning">\#(escape(text))</div>"#
        case .loading:
            return #"<div class="menubar visible loading"><span>\#(escape(MenubarPresentation.loadingChip))</span></div>"#
        case let .visible(segments):
            let chips = segments.map { #"<span>\#(escape($0))</span>"# }.joined(separator: #"<i>·</i>"#)
            return #"<div class="menubar visible">\#(chips)</div>"#
        }
    }

    private static func renderRow(_ row: MenuPresentation.Row) -> String {
        switch row {
        case .separator:
            return #"<div class="sep" role="separator"></div>"#
        case let .text(item):
            let indent = item.indentation > 0 ? " indent-\(item.indentation)" : ""
            return """
            <div class="row text style-\(item.style.rawValue)\(indent)" data-role="\(escape(item.role))">\(escape(item.text))</div>
            """
        case let .meter(item):
            return renderMeter(item)
        case let .model(item):
            return """
            <div class="row model" data-role="model">
              <span class="name">\(escape(item.name))</span>
              <span class="tokens">\(escape(item.tokens))</span>
              <span class="cost">\(escape(item.cost))</span>
            </div>
            """
        case let .action(item):
            let key = item.keyEquivalent.map { " <kbd>\(escape($0))</kbd>" } ?? ""
            return """
            <div class="row action" data-role="\(escape(item.role))">\(escape(item.title))\(key)</div>
            """
        case let .profileSwitcher(item):
            let options = item.options.map { option in
                let mark = option.isSelected ? "✓" : ""
                return """
                <div class="profile-option\(option.isSelected ? " selected" : "")">
                  <span class="check">\(escape(mark))</span>
                  <span class="name">\(escape(option.title))</span>
                </div>
                """
            }.joined(separator: "\n")
            return """
            <div class="row profile-switcher open" data-role="\(escape(item.role))">
              <span class="switcher-title">\(escape(item.title))</span>
              <span class="submenu-arrow" aria-hidden="true">›</span>
              <div class="profile-submenu" role="menu">\(options)</div>
            </div>
            """
        }
    }

    private static func renderMeter(_ item: MenuPresentation.MeterRow) -> String {
        let fraction = UsageFormatting.barFraction(percentUsed: item.content.percentUsed)
        let fillPercent: Double
        if item.content.percentUsed <= 0 {
            fillPercent = 0
        } else {
            fillPercent = max(
                fraction * 100.0,
                MenuLayout.meterBarHeight / (MenuLayout.menuWidth - MenuLayout.insetX * 2) * 100.0
            )
        }
        let subtitle: String
        if let text = item.content.subtitle, !text.isEmpty {
            subtitle = #"<div class="meter-sub">\#(escape(text))</div>"#
        } else {
            subtitle = ""
        }
        let right: String
        if item.content.rightCaption.isEmpty {
            right = ""
        } else {
            right = #"<span class="cap-right">\#(escape(item.content.rightCaption))</span>"#
        }
        return """
        <div class="meter" data-role="\(escape(item.role))" data-level="\(item.level.rawValue)">
          <div class="meter-title">\(escape(item.content.title))</div>
          \(subtitle)
          <div class="bar" role="progressbar" aria-valuenow="\(Int(min(max(item.content.percentUsed, 0), 100).rounded()))">
            <i class="fill level-\(item.level.rawValue)\(fillPercent == 0 ? " zero" : "")" style="width: \(String(format: "%.2f", fillPercent))%"></i>
          </div>
          <div class="caps">
            <span class="cap-left">\(escape(item.content.leftCaption))</span>
            \(right)
          </div>
        </div>
        """
    }

    private static func css(_ appearance: Appearance) -> String {
        let palette: String
        switch appearance {
        case .light:
            palette = """
            :root {
              --stage: #7d7d80;
              --menu: #f4f4f5;
              --line: rgba(0,0,0,0.10);
              --label: #1d1d1f;
              --secondary: #6e6e73;
              --track: rgba(0,0,0,0.14);
              --chip: rgba(255,255,255,0.88);
              --green: #34c759;
              --yellow: #ffcc00;
              --orange: #ff9f0a;
              --red: #ff3b30;
            }
            """
        case .dark:
            palette = """
            :root {
              --stage: #2b2b2e;
              --menu: #2c2c2e;
              --line: rgba(255,255,255,0.10);
              --label: #f5f5f7;
              --secondary: #a1a1a6;
              --track: rgba(255,255,255,0.14);
              --chip: rgba(40,40,42,0.92);
              --green: #30d158;
              --yellow: #ffd60a;
              --orange: #ff9f0a;
              --red: #ff453a;
            }
            """
        }

        return """
        \(palette)
        html, body { margin: 0; padding: 0; background: var(--stage); }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          -webkit-font-smoothing: antialiased;
        }
        .stage {
          display: inline-block;
          padding: 24px;
        }
        .menubar {
          display: inline-flex;
          align-items: center;
          gap: 0;
          height: \(Int(MenuLayout.menubarChipHeight))px;
          padding: 0 10px;
          margin: 0 0 10px 8px;
          border-radius: 6px;
          background: var(--chip);
          color: var(--label);
          font: 500 12px/1 ui-monospace, "SF Mono", Menlo, monospace;
          box-shadow: 0 1px 2px rgba(0,0,0,0.18);
        }
        .menubar.hidden { color: var(--secondary); font-style: italic; }
        .menubar i { margin: 0 6px; color: var(--secondary); font-style: normal; }
        .menu {
          position: relative;
          width: \(Int(MenuLayout.menuWidth))px;
          background: var(--menu);
          border-radius: 8px;
          box-shadow: 0 8px 28px rgba(0,0,0,0.28);
          padding: 6px 0 8px;
          overflow: visible;
        }
        .row {
          padding: 3px \(Int(MenuLayout.insetX))px;
          color: var(--label);
          font-size: 13px;
          line-height: \(Int(MenuLayout.textRowHeight))px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .row.indent-1 { padding-left: \(Int(MenuLayout.insetX) + 16)px; }
        .style-header, .style-section { font-weight: 600; }
        .style-secondary { color: var(--secondary); font-size: 12px; }
        .sep {
          height: \(Int(MenuLayout.separatorHeight))px;
          margin: 0;
          background: none;
          position: relative;
        }
        .sep::after {
          content: "";
          position: absolute;
          left: \(Int(MenuLayout.insetX))px;
          right: \(Int(MenuLayout.insetX))px;
          top: 50%;
          height: 1px;
          margin-top: -0.5px;
          background: var(--line);
        }
        .meter {
          padding: \(Int(MenuLayout.meterInsetTop))px \(Int(MenuLayout.insetX))px \(Int(MenuLayout.meterInsetBottom))px;
        }
        .meter-title {
          font-size: 13px; font-weight: 600; color: var(--label);
          line-height: \(Int(MenuLayout.meterTitleHeight))px;
        }
        .meter-sub {
          margin-top: \(Int(MenuLayout.meterTitleToSubtitle))px;
          font-size: 12px; color: var(--secondary);
          line-height: \(Int(MenuLayout.meterSubtitleHeight))px;
        }
        .bar {
          margin-top: \(Int(MenuLayout.meterTitleToBar))px;
          height: \(Int(MenuLayout.meterBarHeight))px;
          border-radius: 999px;
          background: var(--track);
          overflow: hidden;
        }
        .meter-sub + .bar { margin-top: \(Int(MenuLayout.meterSubtitleToBar))px; }
        .fill { display: block; height: 100%; border-radius: 999px; }
        .fill.zero { min-width: 0; }
        .level-green { background: var(--green); }
        .level-yellow { background: var(--yellow); }
        .level-orange { background: var(--orange); }
        .level-red { background: var(--red); }
        .caps {
          display: flex; justify-content: space-between; gap: \(Int(MenuLayout.meterCaptionGap))px;
          margin-top: \(Int(MenuLayout.meterBarToCaptions))px;
          font: 400 11px/\(Int(MenuLayout.meterCaptionHeight))px ui-monospace, "SF Mono", Menlo, monospace;
          color: var(--secondary);
        }
        .model {
          display: grid;
          grid-template-columns: 1fr \(Int(MenuLayout.tokensColumnWidth))px \(Int(MenuLayout.costColumnWidth))px;
          column-gap: \(Int(MenuLayout.columnGap))px;
          height: \(Int(MenuLayout.modelRowHeight))px;
          align-items: center;
          font-size: 12px;
        }
        .model .tokens { text-align: right; color: var(--secondary); font-variant-numeric: tabular-nums; }
        .model .cost { text-align: right; font-variant-numeric: tabular-nums; }
        .action { font-size: 13px; }
        .row.profile-switcher {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 8px;
          position: relative;
          overflow: visible;
        }
        .row.profile-switcher.open,
        .row.profile-switcher:hover {
          background: rgba(0, 0, 0, 0.06);
        }
        html[data-appearance="dark"] .row.profile-switcher.open,
        html[data-appearance="dark"] .row.profile-switcher:hover {
          background: rgba(255, 255, 255, 0.08);
        }
        .switcher-title {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .submenu-arrow {
          flex: 0 0 auto;
          color: var(--secondary);
          font-size: 16px;
          line-height: 1;
          margin-right: -2px;
        }
        .profile-submenu {
          position: absolute;
          left: calc(100% - 2px);
          top: -6px;
          min-width: 168px;
          margin: 0;
          padding: 6px 0;
          background: var(--menu);
          border-radius: 8px;
          box-shadow: 0 8px 28px rgba(0,0,0,0.28);
          z-index: 3;
        }
        .profile-option {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 3px \(Int(MenuLayout.insetX))px;
          color: var(--label);
          font-size: 13px;
          line-height: \(Int(MenuLayout.textRowHeight))px;
        }
        .profile-option .check {
          width: 14px;
          flex: 0 0 14px;
        }
        kbd {
          float: right;
          font: 500 11px/1 ui-monospace, "SF Mono", Menlo, monospace;
          color: var(--secondary);
        }
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
