#!/bin/sh
set -euo pipefail

swift build -c release --product ToyStack

APP=ToyStack.app
BIN=$(swift build -c release --product ToyStack --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ToyStack" "$APP/Contents/MacOS/ToyStack"
cp -R "$BIN/ToyStack_Engine.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ToyStack</string>
<key>CFBundleIdentifier</key><string>dev.kresna.toystack</string>
<key>CFBundleName</key><string>ToyStack</string>
<key>CFBundleDisplayName</key><string>ToyStack</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
open "$APP"
