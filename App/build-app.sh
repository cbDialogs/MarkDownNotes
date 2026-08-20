#!/bin/zsh
# Assembles MarkDownNotes.app from the release build.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="../MarkDownNotes.app"
BIN=".build/release/MarkDownNotes"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

cp "$BIN" "$APP/Contents/MacOS/MarkDownNotes"
cp Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MarkDownNotes</string>
    <key>CFBundleDisplayName</key><string>MarkDownNotes</string>
    <key>CFBundleIdentifier</key><string>com.clearskycb.MarkDownNotes</string>
    <key>CFBundleExecutable</key><string>MarkDownNotes</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "built: $APP"
