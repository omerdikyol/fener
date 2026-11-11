#!/bin/sh
# Builds a notarized fener.app for both Apple Silicon and Intel and packs it for a release:
# .build/dist/fener-<version>.dmg with its SHA-256, and the Homebrew cask (.build/dist/fener.rb).
#
# Needs a Developer ID Application certificate and notary credentials stored once with
#   xcrun notarytool store-credentials fener-notary --apple-id <apple id> --team-id <team id>
# (FENER_NOTARY_PROFILE picks another profile name).
set -eu
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
PROFILE=${FENER_NOTARY_PROFILE:-fener-notary}
DIST=.build/dist
DMG="$DIST/fener-$VERSION.dmg"

FENER_UNIVERSAL=1 FENER_RELEASE=1 scripts/build-app.sh
rm -rf "$DIST"; mkdir -p "$DIST"

# Apple takes the app as a zip for notarization; the ticket is then stapled to the app itself.
ditto -c -k --keepParent .build/fener.app "$DIST/submit.zip"
xcrun notarytool submit "$DIST/submit.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple .build/fener.app
rm "$DIST/submit.zip"
spctl --assess --type execute --verbose .build/fener.app

# The disk image people download, itself signed, notarized and stapled.
scripts/make-dmg.sh

# The Homebrew cask for this release, for the omerdikyol/homebrew-tap repository (Casks/fener.rb).
SHA=$(cut -d' ' -f1 "$DMG.sha256")
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/homebrew/fener.rb.in > "$DIST/fener.rb"
echo "release: $DMG"
cat "$DMG.sha256"
echo "cask:    $DIST/fener.rb"
