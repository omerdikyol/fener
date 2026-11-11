#!/bin/sh
# Builds fener.app, installs it to ~/Applications, links the command to ~/.local/bin/fener and
# starts it as a LaunchAgent (runs at login, restarted if it crashes). Re-run to update.
#
# See build-app.sh for how the app is signed.
set -eu
cd "$(dirname "$0")/.."

LABEL=io.github.omerdikyol.fener
APP="$HOME/Applications/fener.app"
EXE="$APP/Contents/MacOS/fener"
BIN="$HOME/.local/bin/fener"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STAGE=.build/fener.app

scripts/build-app.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/fener"
rm -rf "$APP"
ditto "$STAGE" "$APP"
ln -sf "$EXE" "$BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$EXE</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/fener/launchd.log</string>
</dict>
</plist>
PLIST

# bootstrap can fail with an I/O error while the old job is still being torn down; retry.
for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && break
    sleep 1
done
sleep 1
"$BIN" ping && echo "fener is running. Try: $BIN toggle"
