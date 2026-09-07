---
name: verify-usage-widget
description: Verify Cursor Usage model output and HTML visual snapshots after UI or billing changes.
---

# Verify the usage widget

This repo is a Swift model plus two views. Do not add a CLI, a text/JSON dump pipeline, or bash test runners.

## Layout

- `Sources/CursorUsageCore` — model. Auth, Cursor HTTP, `UsageClient.load`, `UsageViewModel`, `MenuPresentation`.
- `Sources/CursorUsageHTML` — idempotent HTML renderer for `MenuPresentation`.
- `Sources/CursorUsage` — macOS AppKit menu-bar extra.
- `Tests/CursorUsageTests` — model unit tests and PNG visual snapshots.

## How to verify

1. Unit tests mock Cursor HTTP with `URLProtocol` and assert structured model output (`swift test`).
2. Visual tests render HTML through the model and screenshot it with headless Chrome. Goldens are PNG-only in `Tests/CursorUsageTests/Snapshots`. Chrome plus `python3-pil` are required so the viewport is cropped to the menu.
3. Update goldens only when the look is supposed to change:

```bash
UPDATE_SNAPSHOTS=1 swift test --filter VisualSnapshotTests
```

4. Check every PNG you touched: on-demand sits after Bot and before the cycle total; text is never orange or red; color belongs on progress bars only.

## Product rules

- Team plans title as **Enterprise**, not Pro.
- Unlimited on-demand is information, not an alert.
- Menubar hides API / Bot / $ at 0. Cursor still shows `0%` through `100%`.
- Do not write app types whose only job is to make tests easier. Inject `URLSession` and pass a `DisplayCalendar` when dates matter.
