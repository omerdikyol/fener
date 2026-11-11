#!/bin/sh
# Builds fener.app, installs it to ~/Applications, links the command to ~/.local/bin/fener and
# starts it as a LaunchAgent (runs at login, restarted if it crashes). Re-run to update.
#
# Signing: with a code-signing certificate, macOS (the Keychain, privacy permissions) knows
# the app by its identifier and certificate, so a rebuild is still the same app and nothing
# asks again. FENER_SIGN_IDENTITY picks one (a name or SHA-1 from
# `security find-identity -v -p codesigning`); otherwise the first "Developer ID Application",
# then "Apple Development" identity is used, and without any the app is signed ad hoc, which
# macOS treats as a new app after every rebuild.
set -eu
cd "$(dirname "$0")/.."

LABEL=io.github.omerdikyol.fener
VERSION=0.1.0
APP="$HOME/Applications/fener.app"
EXE="$APP/Contents/MacOS/fener"
BIN="$HOME/.local/bin/fener"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release

identity=${FENER_SIGN_IDENTITY:-}
if [ -z "$identity" ]; then
    ids=$(security find-identity -v -p codesigning 2>/dev/null || true)
    for kind in "Developer ID Application" "Apple Development"; do
        identity=$(printf '%s\n' "$ids" | grep "\"$kind:" | head -1 | awk '{print $2}')
        [ -n "$identity" ] && break
    done
fi

# Build the bundle next to the build products, then swap it in.
STAGE=.build/fener.app
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS"
cp .build/release/fener "$STAGE/Contents/MacOS/fener"
cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>fener</string>
  <key>CFBundleExecutable</key><string>fener</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>fener asks System Events and Finder to restart, shut down, log out or empty the Trash when you pick those.</string>
</dict>
</plist>
PLIST
cat > .build/fener.entitlements <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
ENT

if [ -n "$identity" ]; then
    codesign --force --options runtime --timestamp=none --entitlements .build/fener.entitlements \
        --identifier "$LABEL" --sign "$identity" "$STAGE"
    echo "signed with $(codesign -dv --verbose=2 "$STAGE" 2>&1 | sed -n 's/^Authority=//p' | head -1 | sed 's/ (.*//')"
else
    codesign --force --identifier "$LABEL" --sign - "$STAGE"
    echo "no signing certificate found: signed ad hoc (macOS may ask for permissions again after each rebuild)"
fi
codesign --verify --strict "$STAGE"

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
