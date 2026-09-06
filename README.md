# Cursor Usage

A native macOS menu bar app that shows live Cursor AI usage for the current billing cycle: Cursor, API, and Grok Bot percentages in the menu bar, with a dropdown breakdown by model. The same binary is a CLI (`--help`, `--check`, `--json`) so agents can self-discover options and read the same data without the GUI.

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

Or pass it to the CLI:

```bash
CursorUsage --check --user-data-dir /path/to/your/cursor-data
CursorUsage --auth --json
```

`.env` is gitignored — keep personal paths out of the repo.

## API

The app calls unofficial Cursor dashboard endpoints:

- `GET https://cursor.com/api/usage-summary` — billing cycle percentages
- `POST https://cursor.com/api/dashboard/get-aggregated-usage-events` — per-model breakdown
- `POST https://cursor.com/api/dashboard/get-sand-usage-status` — Grok Bot weekly percent and reset
- `POST https://cursor.com/api/dashboard/get-plan-info` — stated Other Models included allowance and plan price
- `POST https://cursor.com/api/dashboard/get-hard-limit` — on-demand off / limited / unlimited

These endpoints are not public API and may change or break without notice.

Grok Bot (`grok-bot-*` / `sand-*`) rows are listed in their own section. Cursor does not tag third-party models when the bot uses them, so those still appear under API. Each bucket header uses a spend-based pool estimate (`$ used ÷ reported %`). When Cursor publishes an Other Models cap, API also shows `Plan limit: $…`.

The billing footer shows this cycle's subscription plus on-demand spend, and whether on-demand is disabled, limited, or unlimited.

## CLI

The same binary is a CLI. With no arguments it launches the menu bar extra. Unknown flags now exit with status 2 instead of opening the GUI.

Agents should start with:

```bash
# Installed / release binary
CursorUsage --help
CursorUsage --help --json

# swift run swallows some flags; pass them after --
swift run CursorUsage -- --help
swift run CursorUsage -- --help --json
```

`--help --json` is a machine-readable command catalog (commands, options, environment, exit codes, examples). `--check --json` is the stable usage report (`schemaVersion` 1) and matches the menu bar dropdown: membership, billing cycle, total pool, Cursor / API / Bot meters with per-model rows, plan limit, weekly bot window, and on-demand billing.

```bash
CursorUsage --check              # full text report (ASCII meters)
CursorUsage --check --json       # same data as JSON
CursorUsage --compact            # menu-bar one-liner only
CursorUsage --auth --json        # which SQLite DB supplied the session
CursorUsage --self-test          # parser checks, no network
```

Auth overrides (tried before env / `.env`):

```bash
CursorUsage --check --user-data-dir /path/to/cursor-data
CursorUsage --check --state-db /path/to/User/globalStorage/state.vscdb
```

Exit codes: `0` success, `1` auth/API error, `2` invalid arguments.

## Development

```bash
swift build
swift run CursorUsage -- --help
swift run CursorUsage -- --check
```

Release binary only (no `.app` wrapper):

```bash
swift build -c release
.build/release/CursorUsage --help
```

## Polling

- Usage summary: every 30 seconds
- Aggregated breakdown: every 120 seconds

## Future ideas

- Profile switcher for multiple Cursor accounts
- Cursor extension port
- Optional LaunchAgent template for start-at-login
- Notarized release zip for people without a Swift toolchain
