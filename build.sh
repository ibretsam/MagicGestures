#!/bin/sh
# Builds MagicGestures.app next to this script.
set -e
cd "$(dirname "$0")"
APP=MagicGestures.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/MagicGestures"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.magicgestures</string>
  <key>CFBundleName</key><string>MagicGestures</string>
  <key>CFBundleExecutable</key><string>MagicGestures</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
# Sign with a real development identity when one exists, so macOS keeps the
# Accessibility grant across rebuilds; otherwise fall back to ad-hoc signing.
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP" || codesign --force --sign - "$APP"
echo "Built $APP"
