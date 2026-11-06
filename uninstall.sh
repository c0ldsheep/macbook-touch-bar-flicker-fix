#!/bin/bash
# Removes tbkeep and gives the Touch Bar back to macOS (auto-brightness and normal dimming).
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, without sudo."
  exit 1
fi
LABEL="local.tbkeep"
DEST="$HOME/Library/Application Support/tbkeep"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ -x "$DEST/tbkeep" ]; then
  if ! "$DEST/tbkeep" auto; then
    echo "Could not restore Touch Bar state; keeping the binary for recovery."
    exit 1
  fi
fi
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/Library/Logs/tbkeep.log"
if [ -L "$HOME/.local/bin/tbkeep" ]; then rm -f "$HOME/.local/bin/tbkeep"; fi
rm -rf "$DEST"
echo "tbkeep removed. The Touch Bar is back to macOS's normal behaviour."
