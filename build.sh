#!/usr/bin/env bash
# Build a macOS .app bundle for winmove.
#
# Usage:
#   ./build_app.sh          # Debug build
#   ./build_app.sh release  # Release build
#
# Output: ./build/winmove.app
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/winmove.app"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/winmove" "$APP/Contents/MacOS/winmove"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
cp "$ROOT/Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

# Ad-hoc sign so AX / event taps are bound to a stable identity.
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built $APP"
echo
echo "Next steps:"
echo "  1. open \"$APP\""
echo "  2. Grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)."
echo "  3. Hold ⌃⌥⌘ and tap ← / → / ↑ / ↓ / Space / Return."
