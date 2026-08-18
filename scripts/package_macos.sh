#!/usr/bin/env bash
#
# Builds Caduceus.app and wraps it in a DMG.
#
# The result is ad-hoc signed, which is enough to run on the machine that
# built it and nowhere else: macOS will refuse to open it on someone else's
# Mac with "Caduceus is damaged and can't be opened". Making it distributable
# needs an Apple Developer ID and a notarisation round trip, which this script
# deliberately does not attempt — see the end of the output.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="flutter_app/build/macos/Build/Products/Release"
APP="$APP_DIR/Caduceus.app"
VERSION="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' flutter_app/pubspec.yaml)"
OUT="dist"
DMG="$OUT/Caduceus-$VERSION.dmg"

echo "==> building $VERSION"
(cd flutter_app && flutter build macos --release)

[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

echo "==> staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The Applications symlink is what makes the window a drag-to-install target.
ln -s /Applications "$STAGE/Applications"

echo "==> packing"
mkdir -p "$OUT"
rm -f "$DMG"
hdiutil create \
  -volname "Caduceus $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo
echo "built: $DMG"
echo "       $(du -h "$DMG" | cut -f1)"
codesign -dv "$APP" 2>&1 | grep -E 'Signature|Format' || true

cat <<'NOTE'

This DMG is ad-hoc signed. It runs on this Mac and will be refused on others.
To distribute it you need an Apple Developer account, and these steps have to
be run by whoever holds it:

  codesign --deep --force --options runtime --timestamp \
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \
    flutter_app/build/macos/Build/Products/Release/Caduceus.app

  xcrun notarytool submit dist/Caduceus-VERSION.dmg \
    --apple-id you@example.com --team-id TEAMID --wait

  xcrun stapler staple dist/Caduceus-VERSION.dmg

Re-run this script after signing the .app so the DMG contains the signed copy.
NOTE
