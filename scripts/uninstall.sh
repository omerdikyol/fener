#!/bin/sh
# Stops the LaunchAgent and removes the app and the command. Leaves ~/.config/fener, the
# clipboard history and the cache alone.
set -eu
LABEL=io.github.omerdikyol.fener
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/fener"
rm -rf "$HOME/Applications/fener.app"
echo "fener removed"
