# Cursor Usage

A native macOS menu bar app that shows live Cursor AI usage for the current billing cycle: API usage and first-party (Cursor) usage as percentages in the menu bar, with a dropdown breakdown by model.

## Requirements

- macOS 13+
- Cursor signed in on this Mac
- To **build**: Xcode Command Line Tools (`xcode-select --install`)
- To **run a prebuilt `.app`**: no Swift toolchain needed

## Install (recommended)

From this directory:

```bash
./scripts/build-app.sh
open dist/CursorUsage.app
```

Or copy it into Applications and optionally keep it in the Dock for one-click launch:

```bash
./scripts/build-app.sh
cp -R dist/CursorUsage.app /Applications/
open -a "Cursor Usage"
```

The app is a menu bar extra (`LSUIElement`) — it does not stay in the Dock while running. Dragging the `.app` into the Dock is only a launcher shortcut.

Quit from the menu bar dropdown, or:

```bash
pkill -x CursorUsage
```

### Optional: start at login

Use macOS **System Settings → General → Login Items**, or a LaunchAgent you own. This project does not install a background service for you.

## Authentication

Cursor stores a session token in a local SQLite database. This app reads it read-only via `/usr/bin/sqlite3` (the DB is locked while Cursor is running).

Candidate databases are tried in order until one yields a token:

1. `CURSOR_STATE_DB` — env var or `.env` (direct path to `state.vscdb`)
2. `CURSOR_USER_DATA_DIR` — env var or `.env` (`…/User/globalStorage/state.vscdb` under that dir)
3. `--user-data-dir` from any running Cursor process (most recently modified DB first)
4. `~/Library/Application Support/Cursor` — the normal default install

The JWT payload is decoded to extract the user ID, which is combined with the token into a `WorkosCursorSessionToken` cookie for API requests. No token is stored by this app.

### Custom Cursor profiles

If you launch Cursor with `--user-data-dir` (e.g. separate work and personal profiles), either:

- Leave Cursor running and let auto-discovery pick it up, or
- Set `CURSOR_USER_DATA_DIR` in a `.env` file

`.env` search order:

1. `~/Library/Application Support/CursorUsage/.env` (best for the packaged app)
2. Next to `CursorUsage.app`
3. Package / project directory when developing with `swift run`

```bash
mkdir -p "$HOME/Library/Application Support/CursorUsage"
cp .env.example "$HOME/Library/Application Support/CursorUsage/.env"
# then set CURSOR_USER_DATA_DIR=…
```

Ask an agent to find your directory from running processes:

```bash
ps -ax -o args= | grep -i 'Cursor.*--user-data-dir'
```

`.env` is gitignored — keep personal paths out of the repo.

## API

The app calls unofficial Cursor dashboard endpoints:

- `GET https://cursor.com/api/usage-summary` — billing cycle percentages
- `POST https://cursor.com/api/dashboard/get-aggregated-usage-events` — per-model breakdown

These endpoints are not public API and may change or break without notice.

## Development

```bash
swift build
swift run CursorUsage
```

Self-check (no GUI — prints usage to stdout, including which DB path won):

```bash
swift run CursorUsage --check
```

Release binary only (no `.app` wrapper):

```bash
swift build -c release
.build/release/CursorUsage
```

## Polling

- Usage summary: every 30 seconds
- Aggregated breakdown: every 120 seconds

## Future ideas

- Profile switcher for multiple Cursor accounts
- Cursor extension port
- Optional LaunchAgent template for start-at-login
- Notarized release zip for people without a Swift toolchain
