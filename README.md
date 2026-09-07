# Cursor Usage

A native macOS menu bar app that shows live Cursor usage for the current billing cycle.

The Swift model fetches usage with your local Cursor session. Two views render that model:

- **AppKit** — the macOS menu-bar extra
- **HTML** — an idempotent renderer used for visual snapshots, and a starting point for a later non-Mac shell

Agent-facing usage lookup does not belong in this binary. If you want a tool an agent can call, host a small MCP or serverless API later and keep the Cursor token in that host's secrets.

## Requirements

- macOS 13+
- Cursor signed in on this Mac
- To **build**: Xcode Command Line Tools (`xcode-select --install`)
- To **run a prebuilt `.app`**: no Swift toolchain needed

## Install

From this directory:

```bash
./scripts/build-app.sh
open dist/CursorUsage.app
```

Or copy it into Applications:

```bash
./scripts/build-app.sh
cp -R dist/CursorUsage.app /Applications/
open -a "Cursor Usage"
```

The app is a menu bar extra (`LSUIElement`). Quit from the dropdown, or `pkill -x CursorUsage`.

Optional: add it under **System Settings → General → Login Items**.

## Authentication

Cursor stores a session token in a local SQLite database. This app reads it read-only via `/usr/bin/sqlite3`.

Candidate databases, in order:

1. The profile last picked in the dropdown
2. `CURSOR_STATE_DB` — env var or `.env`
3. `CURSOR_USER_DATA_DIR` — env var or `.env`
4. `--user-data-dir` from any running Cursor process
5. `~/Library/Application Support/Cursor`
6. Other `~/Library/Application Support/Cursor*` folders that contain a session database
7. Profiles you have switched to before

If more than one signed-in account is detected, the first section shows **Current profile: \<name\>**. Hover to open a submenu and switch. That row is hidden when only one account exists. The same Cursor account in both Default and a named `--user-data-dir` shows only the named profile.

`.env` search order:

1. `~/Library/Application Support/CursorUsage/.env`
2. Next to `CursorUsage.app`
3. The package directory when developing with `swift run`

```bash
mkdir -p "$HOME/Library/Application Support/CursorUsage"
cp .env.example "$HOME/Library/Application Support/CursorUsage/.env"
```

## What it shows

- Cursor, API, and Grok Bot included usage
- On-demand spend after Bot and before the cycle total
- Plan + on-demand as the cycle total
- Team on-demand split into you vs everyone else

Progress-bar color is the only place yellow / orange / red appear. Unlimited on-demand is plain text.

These Cursor dashboard endpoints are unofficial and may change:

- `GET /api/usage-summary`
- `POST /api/dashboard/get-aggregated-usage-events`
- `POST /api/dashboard/get-sand-usage-status`
- `POST /api/dashboard/get-plan-info`
- `POST /api/dashboard/get-hard-limit`

## Development

```bash
swift build
swift test
```

`swift test` runs the model unit tests and the HTML visual snapshots. Chrome is required for the PNG checks, and `python3-pil` crops the viewport to the menu. Visual compare allows Chrome font antialiasing: it checks crop size and progress-bar colors, not raw PNG bytes. Rewrite goldens with:

```bash
UPDATE_SNAPSHOTS=1 swift test --filter VisualSnapshotTests
```

Linux CI runs the same `swift test` command. The AppKit target is macOS-only.

## Polling

- Usage summary: every 30 seconds
- Aggregated breakdown: every 120 seconds
