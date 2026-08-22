#!/bin/zsh
# Builds a Developer ID signed, notarized, stapled MarkDownNotes DMG.
# Credentials: the AC_NOTARY notarytool keychain profile, shared with the
# other Dialogs projects. If it goes missing, re-create it with
# `xcrun notarytool store-credentials AC_NOTARY --team-id 54MH33556M`.
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
xcrun notarytool submit "$STAGE/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait < /dev/null
xcrun stapler staple "$APP"

echo "==> Building DMG"
mkdir "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "MarkDownNotes" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG"

echo "==> Notarizing DMG"
codesign --timestamp -s "$SIGN_IDENTITY" "$DMG"
# notarytool stalls uploading a file that lives on an external volume —
# it sleeps forever without ever opening a connection. Submit from a
# local copy, then staple the original.
UPLOAD_DIR=~/Library/Caches/markdownnotes-release
mkdir -p "$UPLOAD_DIR"
cp "$DMG" "$UPLOAD_DIR/"
xcrun notarytool submit "$UPLOAD_DIR/$(basename "$DMG")" \
    --keychain-profile "$NOTARY_PROFILE" --wait < /dev/null
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl -a -t exec -vv "$APP"
echo "notarized: $DMG"
