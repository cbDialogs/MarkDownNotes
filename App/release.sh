#!/bin/zsh
# Builds a Developer ID signed, notarized, stapled MarkDownNotes DMG.
# Credentials: a notarytool keychain profile (default AC_NOTARY, the same
# profile the other Dialogs projects use).
set -e
cd "$(dirname "$0")"

: "${SIGN_IDENTITY:=Developer ID Application: Dialogs Apps, Inc. (54MH33556M)}"
: "${NOTARY_PROFILE:=AC_NOTARY}"

VERSION=$(sed -n 's/.*CFBundleShortVersionString<\/key><string>\([^<]*\).*/\1/p' build-app.sh)
APP=../MarkDownNotes.app
DMG=../MarkDownNotes-$VERSION.dmg

./build-app.sh

echo "==> Signing with Developer ID + hardened runtime"
codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "==> Notarizing app"
ditto -c -k --keepParent "$APP" "$STAGE/app.zip"
xcrun notarytool submit "$STAGE/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> Building DMG"
mkdir "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "MarkDownNotes" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG"

echo "==> Notarizing DMG"
codesign --timestamp -s "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl -a -t exec -vv "$APP"
echo "notarized: $DMG"
