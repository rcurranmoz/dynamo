#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Dynamo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos13.0 main.swift -o "$APP/Contents/MacOS/Dynamo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dynamo</string>
  <key>CFBundleExecutable</key><string>Dynamo</string>
  <key>CFBundleIdentifier</key><string>com.mozilla.relops.dynamo</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
PLIST
echo '</plist>' >> "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
