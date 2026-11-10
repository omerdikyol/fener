#!/bin/sh
# Stops the LaunchAgent and removes the binary. Leaves ~/.config/fener and the cache alone.
set -eu
LABEL=io.github.omerdikyol.fener
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/fener"
echo "fener removed"
