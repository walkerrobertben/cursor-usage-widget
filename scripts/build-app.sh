#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Cursor Usage"
BUNDLE_NAME="CursorUsage.app"
DIST_DIR="${ROOT}/dist"
APP_PATH="${DIST_DIR}/${BUNDLE_NAME}"

echo "Building release binary…"
swift build -c release

BINARY="${ROOT}/.build/release/CursorUsage"
if [[ ! -x "$BINARY" ]]; then
  echo "error: expected binary at $BINARY" >&2
  exit 1
fi

echo "Packaging ${BUNDLE_NAME}…"
rm -rf "$APP_PATH"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "$BINARY" "${APP_PATH}/Contents/MacOS/CursorUsage"
cp "${ROOT}/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

# Ad-hoc sign so macOS will launch a locally built app more reliably.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH"
fi

echo
echo "Built: ${APP_PATH}"
echo
echo "Install options:"
echo "  open \"${APP_PATH}\""
echo "  cp -R \"${APP_PATH}\" /Applications/"
echo "  # then optionally drag Cursor Usage from /Applications into the Dock"
echo
echo "Custom Cursor profile (optional):"
echo "  mkdir -p \"\$HOME/Library/Application Support/CursorUsage\""
echo "  cp .env.example \"\$HOME/Library/Application Support/CursorUsage/.env\""
echo
echo "CLI (same binary, no GUI):"
echo "  \"${APP_PATH}/Contents/MacOS/CursorUsage\" --help"
echo "  \"${APP_PATH}/Contents/MacOS/CursorUsage\" --check"
