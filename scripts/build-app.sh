#!/bin/sh
# Builds and signs .build/fener.app. Used by install.sh and release.sh.
#
# Signing: with a code-signing certificate, macOS (the Keychain, privacy permissions) knows
# the app by its identifier and certificate, so a rebuild is still the same app and nothing
# asks again. FENER_SIGN_IDENTITY picks one (a name or SHA-1 from
# `security find-identity -v -p codesigning`); otherwise the first "Developer ID Application",
# then "Apple Development" identity is used, and without any the app is signed ad hoc, which
# macOS treats as a new app after every rebuild.
#
# FENER_UNIVERSAL=1 builds for Apple Silicon and Intel; FENER_RELEASE=1 also requires a
# Developer ID certificate and adds the secure timestamp notarization needs.
set -eu
cd "$(dirname "$0")/.."

LABEL=io.github.omerdikyol.fener
VERSION=$(cat VERSION)

if [ "${FENER_UNIVERSAL:-}" = 1 ]; then
    swift build -c release --arch arm64 --arch x86_64
    BUILT=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/fener
else
    swift build -c release
    BUILT=.build/release/fener
fi

identity=${FENER_SIGN_IDENTITY:-}
kinds="Developer ID Application"
[ "${FENER_RELEASE:-}" = 1 ] || kinds="$kinds|Apple Development"
if [ -z "$identity" ]; then
    ids=$(security find-identity -v -p codesigning 2>/dev/null || true)
    IFS='|'
    for kind in $kinds; do
        identity=$(printf '%s\n' "$ids" | grep "\"$kind:" | head -1 | awk '{print $2}')
        [ -n "$identity" ] && break
    done
    unset IFS
fi
if [ "${FENER_RELEASE:-}" = 1 ] && [ -z "$identity" ]; then
    echo "a release needs a Developer ID Application certificate" >&2; exit 1
fi


# The bundle.
STAGE=.build/fener.app
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS"
cp "$BUILT" "$STAGE/Contents/MacOS/fener"
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
    codesign --force --options runtime $([ "${FENER_RELEASE:-}" = 1 ] && echo --timestamp || echo --timestamp=none) --entitlements .build/fener.entitlements \
        --identifier "$LABEL" --sign "$identity" "$STAGE"
    echo "signed with $(codesign -dv --verbose=2 "$STAGE" 2>&1 | sed -n 's/^Authority=//p' | head -1 | sed 's/ (.*//')"
else
    codesign --force --identifier "$LABEL" --sign - "$STAGE"
    echo "no signing certificate found: signed ad hoc (macOS may ask for permissions again after each rebuild)"
fi
codesign --verify --strict "$STAGE"

