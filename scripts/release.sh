#!/bin/sh
# Builds a release of Ko'prik: Release build -> .app -> .dmg, and, when a
# Sparkle key exists, signs the .dmg and adds an entry to appcast.xml.
#
# Usage: scripts/release.sh <version> <build-number> [download-url-base]
#   version            marketing version, e.g. 0.2.0
#   build-number       integer that grows with every release, e.g. 2
#   download-url-base  where the .dmg will be published, e.g.
#                      https://github.com/OWNER/koprik/releases/download/v0.2.0
#
# Nothing is uploaded or pushed: publishing stays a separate, deliberate step.
# There is no paid Apple Developer account, so the app is signed ad hoc and
# not notarised. That is enough on this Mac; other Macs will need
# right-click > Open the first time.
set -eu

VERSION=${1:?version, e.g. 0.2.0}
BUILD=${2:?build number, e.g. 2}
URL_BASE=${3:-}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/release"
DERIVED="$ROOT/build/DerivedData-release"
APP="$OUT/Koprik.app"
DMG="$OUT/Koprik-$VERSION.dmg"

cd "$ROOT"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Generating project"
xcodegen generate --quiet

echo "==> Building Release $VERSION ($BUILD)"
xcodebuild build \
  -project Koprik.xcodeproj -scheme Koprik -configuration Release \
  -destination "platform=macOS" -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
test -d "$DERIVED/Build/Products/Release/Koprik.app" || { echo "build failed"; exit 1; }
ditto "$DERIVED/Build/Products/Release/Koprik.app" "$APP"

echo "==> Signing ad hoc"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Creating disk image"
create-dmg \
  --volname "Ko'prik $VERSION" \
  --window-pos 200 120 --window-size 660 400 \
  --icon-size 128 --icon "Koprik.app" 180 170 \
  --app-drop-link 480 170 --hide-extension "Koprik.app" \
  --no-internet-enable \
  "$DMG" "$APP" >/dev/null
echo "    $DMG ($(du -h "$DMG" | cut -f1))"

# Left on disk, these copies get registered with Launch Services and can
# answer koprik:// links instead of the installed app.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for copy in "$APP" "$DERIVED/Build/Products/Release/Koprik.app"; do
  "$LSREGISTER" -u "$copy" 2>/dev/null || true
  rm -rf "$copy"
done

SIGN_UPDATE=$(find "$ROOT/build" ~/Library/Developer/Xcode/DerivedData -name sign_update -type f -perm -u+x 2>/dev/null | head -1)
if [ -z "$SIGN_UPDATE" ]; then
  echo "==> Sparkle sign_update not found; skipping appcast. Build once in Xcode first."
  exit 0
fi
if [ -z "$URL_BASE" ]; then
  echo "==> No download URL given; skipping appcast."
  exit 0
fi

echo "==> Signing update and writing appcast entry"
SIGNATURE=$("$SIGN_UPDATE" "$DMG") || {
  echo "    sign_update failed: create a key first with generate_keys (see docs/RELIZ.md)"
  exit 1
}
DATE=$(date -R)
ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url=\"$URL_BASE/Koprik-$VERSION.dmg\" type=\"application/octet-stream\" $SIGNATURE />
    </item>"
# Newest entry goes first, right after the channel description.
awk -v item="$ITEM" '{ print } /<\/language>/ && !done { print item; done = 1 }' appcast.xml > "$OUT/appcast.xml"
mv "$OUT/appcast.xml" appcast.xml
echo "    appcast.xml updated. Review it, then publish the .dmg and the appcast."
