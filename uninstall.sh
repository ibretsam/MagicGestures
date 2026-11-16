#!/bin/sh
# Removes MagicGestures and its login item. Your gestures in ~/.config/magicgestures are kept.
launchctl bootout "gui/$(id -u)/local.magicgestures" 2>/dev/null || true
pkill -f MagicGestures.app/Contents/MacOS 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.magicgestures.plist"
rm -rf /Applications/MagicGestures.app
echo "MagicGestures removed. Delete ~/.config/magicgestures to remove your gestures too."
