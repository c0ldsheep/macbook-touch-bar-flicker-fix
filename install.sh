#!/bin/bash
# Installs tbkeep, the MacBook Pro Touch Bar flicker fix.
# Builds tbkeep from source on this Mac and starts it at every login. No admin password needed.
# Running it again updates an existing install and keeps your level.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="local.tbkeep"
DEST="$HOME/Library/Application Support/tbkeep"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LINK_DIR="$HOME/.local/bin"

echo "Installing the Touch Bar flicker fix (tbkeep)..."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This only works on a Mac."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
  echo
  echo "Apple's free Command Line Tools are needed to build tbkeep."
  echo "A window will open: click Install and wait until it finishes. Then run ./install.sh again."
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi

# Build into a new file and check this Mac before installing anything.
mkdir -p "$DEST"
rm -f "$DEST/tbkeep.new"
clang -fobjc-arc -O2 -framework Foundation -framework AppKit tbkeep.m -o "$DEST/tbkeep.new"
if ! "$DEST/tbkeep.new" check; then
  rm -f "$DEST/tbkeep.new"
  echo "Nothing was installed."
  exit 1
fi
mv -f "$DEST/tbkeep.new" "$DEST/tbkeep"
cp uninstall.sh "$DEST/uninstall.sh"
chmod +x "$DEST/uninstall.sh"
[ -f "$DEST/level" ] || echo "0.60" > "$DEST/level"

# Start at every login. KeepAlive restarts tbkeep if it crashes, but not after it stops on purpose.
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST/tbkeep</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/tbkeep.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
sleep 1
if ! launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null; then
  sleep 2
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi

# The tbkeep command.
mkdir -p "$LINK_DIR"
if [ -e "$LINK_DIR/tbkeep" ] && [ ! -L "$LINK_DIR/tbkeep" ]; then
  echo "Note: $LINK_DIR/tbkeep already exists and is not tbkeep, so it was left alone."
else
  ln -sf "$DEST/tbkeep" "$LINK_DIR/tbkeep"
fi

sleep 1
echo
"$DEST/tbkeep" status
echo
echo "Done. The Touch Bar now stays at a level where it does not flicker."
case ":$PATH:" in
  *":$LINK_DIR:"*)
    echo "Change the level any time with: tbkeep 70   (all commands: tbkeep help)" ;;
  *)
    echo "Change the level any time with: \"$DEST/tbkeep\" 70"
    echo "To type just 'tbkeep', run this once and open a new Terminal window:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
esac
