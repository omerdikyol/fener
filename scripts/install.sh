#!/bin/sh
# Builds fener, installs it to ~/.local/bin and starts it as a LaunchAgent
# (runs at login, restarted if it crashes). Re-run to update.
set -eu
cd "$(dirname "$0")/.."

LABEL=io.github.omerdikyol.fener
BIN="$HOME/.local/bin/fener"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/fener"
install -m 755 .build/release/fener "$BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/fener/launchd.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootstrap can fail with an I/O error while the old job is still being torn down; retry.
for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && break
    sleep 1
done
sleep 1
"$BIN" ping && echo "fener is running. Try: $BIN toggle"
