#!/bin/bash
# Removes tbkeep and gives the Touch Bar back to macOS (auto-brightness and normal dimming).
LABEL="local.tbkeep"
DEST="$HOME/Library/Application Support/tbkeep"

if [ -x "$DEST/tbkeep" ]; then "$DEST/tbkeep" auto >/dev/null 2>&1; fi
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/Library/Logs/tbkeep.log"
if [ -L "$HOME/.local/bin/tbkeep" ]; then rm -f "$HOME/.local/bin/tbkeep"; fi
rm -rf "$DEST"
echo "tbkeep removed. The Touch Bar is back to macOS's normal behaviour."
