#!/bin/sh
# Builds Ko'prik in Release mode and installs it as /Applications/Koprik.app,
# so Spotlight, Launchpad and `open -a Koprik` all start the same, complete copy.
#
# Build products left in DerivedData are also registered with Launch Services.
# A half-finished one (for example a build that stopped before Sparkle was
# embedded) then gets picked instead and dies at launch without a window,
# so those copies are unregistered here.
#
# Usage: scripts/install.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DERIVED="$ROOT/build/DerivedData-install"
TARGET=/Applications/Koprik.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cd "$ROOT"
xcodegen generate --quiet

echo "==> Building Release"
xcodebuild build \
  -project Koprik.xcodeproj -scheme Koprik -configuration Release \
  -destination "platform=macOS" -derivedDataPath "$DERIVED" \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
BUILT="$DERIVED/Build/Products/Release/Koprik.app"
test -x "$BUILT/Contents/MacOS/Koprik" || { echo "build failed"; exit 1; }
test -d "$BUILT/Contents/Frameworks/Sparkle.framework" || { echo "Sparkle.framework missing from the build"; exit 1; }

echo "==> Installing to $TARGET"
osascript -e 'quit app "Koprik"' >/dev/null 2>&1 || true
# A copy left running keeps the old code in memory and goes on answering links.
for _ in 1 2 3 4 5; do pgrep -x Koprik >/dev/null || break; sleep 1; done
pkill -x Koprik 2>/dev/null || true
rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
# Sign inside out. --deep would re-sign the Quick Look extension without its
# sandbox entitlement, and macOS refuses to load an unsandboxed extension.
codesign --force --sign - --entitlements "$ROOT/KoprikThumbnail/KoprikThumbnail.entitlements" \
  "$TARGET/Contents/PlugIns/KoprikThumbnail.appex"
codesign --force --sign - "$TARGET"
codesign --verify --deep --strict "$TARGET"

echo "==> Unregistering build copies"
find "$ROOT/build" "$HOME/Library/Developer/Xcode/DerivedData" -name Koprik.app -type d -prune 2>/dev/null |
  while read -r copy; do "$LSREGISTER" -u "$copy" 2>/dev/null || true; done
rm -rf "$BUILT"
"$LSREGISTER" -f "$TARGET"

echo "    Installed. Open it with Spotlight, Launchpad or: open -a Koprik"
