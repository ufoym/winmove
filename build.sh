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
# Strip local symbols to reduce binary size.
strip -x "$APP/Contents/MacOS/winmove"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
cp "$ROOT/Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

# Ad-hoc sign so AX / event taps are bound to a stable identity.
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built $APP"

# Package a .dmg for release builds.
if [ "$CONFIG" = "release" ]; then
  DMG="$OUT/WinMove.dmg"
  STAGE="$OUT/dmg-stage"
  TMP_DMG="$OUT/WinMove.tmp.dmg"

  echo "→ packaging $DMG"
  rm -rf "$STAGE" "$DMG" "$TMP_DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/winmove.app"
  ln -s /Applications "$STAGE/Applications"

  # Use the app icon as the volume icon.
  cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
  SetFile -a C "$STAGE" 2>/dev/null || true

  # Build a read/write dmg first so we can set the volume's custom-icon bit,
  # then convert to a compressed read-only dmg.
  hdiutil create \
    -volname "WinMove" \
    -srcfolder "$STAGE" \
    -ov -format UDRW \
    "$TMP_DMG" >/dev/null

  MOUNT_DIR="$(mktemp -d)"
  hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  hdiutil detach "$MOUNT_DIR" -quiet
  rmdir "$MOUNT_DIR" 2>/dev/null || true

  hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG" >/dev/null
  rm -f "$TMP_DMG"
  rm -rf "$STAGE"
  echo "✓ Built $DMG"

  # Inject real artifact sizes into intro.html so the landing page stays honest.
  INTRO="$ROOT/intro.html"
  if [ -f "$INTRO" ]; then
    # App bundle size — human readable (e.g. "1.2M" → "1.2 MB").
    APP_RAW="$(du -sh "$APP" | awk '{print $1}')"
    APP_PRETTY="$(echo "$APP_RAW" | sed -E 's/([0-9.]+)([KMG])/\1 \2B/')"
    # DMG size in KB (rounded), e.g. "842 KB".
    DMG_KB="$(($(stat -f%z "$DMG") / 1024)) KB"

    # Use a temp file + perl for safe in-place replacement of the marker spans.
    perl -0777 -i -pe "s|<!--APP_SIZE-->.*?<!--/APP_SIZE-->|<!--APP_SIZE-->${APP_PRETTY}<!--/APP_SIZE-->|g" "$INTRO"
    perl -0777 -i -pe "s|<!--DMG_SIZE-->.*?<!--/DMG_SIZE-->|<!--DMG_SIZE-->${DMG_KB}<!--/DMG_SIZE-->|g" "$INTRO"
    echo "✓ Updated intro.html sizes (app=${APP_PRETTY}, dmg=${DMG_KB})"
  fi
fi

echo
echo "Next steps:"
echo "  1. open \"$APP\""
echo "  2. Grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)."
echo "  3. Hold ⌃⌥⌘ and tap ← / → / ↑ / ↓ / Space / Return."
