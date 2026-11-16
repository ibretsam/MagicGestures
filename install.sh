#!/bin/sh
# Builds MagicGestures, installs it to /Applications, and sets it to start at login.
set -e
cd "$(dirname "$0")"

sh build.sh

AGENT="$HOME/Library/LaunchAgents/local.magicgestures.plist"
CONFIG_DIR="$HOME/.config/magicgestures"
DOMAIN="gui/$(id -u)"

# Stop any running copy before replacing it.
launchctl bootout "$DOMAIN/local.magicgestures" 2>/dev/null || true
pkill -f MagicGestures.app/Contents/MacOS 2>/dev/null || true
sleep 1

rm -rf /Applications/MagicGestures.app
ditto MagicGestures.app /Applications/MagicGestures.app

# Install the gestures from this repository unless a config already exists.
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  cp config.json "$CONFIG_DIR/config.json"
  echo "Installed gestures to $CONFIG_DIR/config.json"
else
  echo "Kept existing $CONFIG_DIR/config.json"
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.magicgestures</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/MagicGestures.app/Contents/MacOS/MagicGestures</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap "$DOMAIN" "$AGENT"

echo "MagicGestures is installed and running. Look for the hand icon in the menu bar."
echo "Grant it Accessibility access when macOS asks (System Settings > Privacy & Security > Accessibility)."
