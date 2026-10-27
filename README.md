# Cursor Usage

A native macOS menu bar app that shows live Cursor usage for the current billing cycle.

The Swift model fetches usage with your local Cursor session. Two views render that model:

- **AppKit** — the macOS menu-bar extra
- **HTML** — an idempotent renderer used for visual snapshots, and a starting point for a later non-Mac shell

## Requirements

- macOS 13+
- Cursor signed in on this Mac
- To **build**: Swift 5.9+ from Xcode or Xcode Command Line Tools (`xcode-select --install`)
- To **run a prebuilt `.app`**: no Swift toolchain needed

## Install

Clone the repository, then build locally:

```bash
git clone https://github.com/walkerrobertben/cursor-usage-widget.git
cd cursor-usage-widget
./scripts/build-app.sh
open dist/CursorUsage.app
```

Or copy it into Applications:

```bash
./scripts/build-app.sh
cp -R dist/CursorUsage.app /Applications/
open -a "Cursor Usage"
```

The app appears in the menu bar, with no Dock icon. Quit from the dropdown, or `pkill -x CursorUsage`.

The script builds for your Mac's architecture and ad-hoc signs the app. It does not produce a notarized download; friends should build their own copy using these steps.

Optional: add it under **System Settings → General → Login Items**.

## Authentication

Cursor stores a session token in a local SQLite database. This app reads it read-only via `/usr/bin/sqlite3`.

No API key or manual token entry is required. The session token is sent to `https://cursor.com` to request dashboard data. The app has no analytics or separate backend; it remembers selected profile paths in local preferences.

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
- `POST /api/dashboard/get-me`
- `POST /api/dashboard/get-team-spend`

The model and test fixtures cover legacy monthly Cursor plans with separate Cursor, API, and Bot usage. Newer weekly subscription pools and prepaid-credit plans have not been verified. Treat the cycle bill as an estimate: team seat prices assume monthly USD list prices and do not account for annual discounts, tax, or credits. Check the Cursor dashboard for authoritative usage and billing.

## Troubleshooting

- **Some sections are missing:** optional dashboard requests can fail independently. Compare with **Open Dashboard**; an upstream API change may require a code update.

## Development

```bash
swift build
swift test --skip VisualSnapshotTests
```

The package has no third-party Swift dependencies. Unit tests use synthetic fixtures and mock HTTP requests; they do not need your Cursor account.

`swift test` also runs HTML visual snapshots. Chrome is required for PNG checks (`CHROME_PATH` can point to a custom installation). The snapshot helper uses `/usr/bin/python3`, so Pillow must be available to that interpreter. On macOS, install it into an ignored project-local directory and run:

```bash
/usr/bin/python3 -m pip install --target .snapshot-deps 'Pillow<12'
PYTHONPATH="$PWD/.snapshot-deps${PYTHONPATH:+:$PYTHONPATH}" swift test
```

On Ubuntu, install `python3-pil` instead. Visual compare allows Chrome font antialiasing: it checks crop size and progress-bar colors, not raw PNG bytes. Missing Chrome skips the screenshot tests; missing Pillow causes failures.

CI splits that into two parallel jobs: **Unit tests** (`swift test --skip VisualSnapshotTests`) and **Snapshot tests** (`swift test --filter VisualSnapshotTests`). The AppKit target is macOS-only.

Rewrite goldens with:

```bash
PYTHONPATH="$PWD/.snapshot-deps${PYTHONPATH:+:$PYTHONPATH}" UPDATE_SNAPSHOTS=1 swift test --filter VisualSnapshotTests
```

## Polling

The app reloads summary and breakdown data every 30 seconds, with an additional refresh timer every 120 seconds. **Refresh Now** also reloads all data. Opening the menu rescans local profiles.
