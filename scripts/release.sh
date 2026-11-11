#!/bin/sh
# Builds a notarized fener.app for both Apple Silicon and Intel and zips it for a release:
# .build/dist/fener-<version>.zip, its SHA-256, and the Homebrew cask (.build/dist/fener.rb).
#
# Needs a Developer ID Application certificate and notary credentials stored once with
#   xcrun notarytool store-credentials fener-notary --apple-id <apple id> --team-id <team id>
# (FENER_NOTARY_PROFILE picks another profile name).
set -eu
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
PROFILE=${FENER_NOTARY_PROFILE:-fener-notary}
DIST=.build/dist
ZIP="$DIST/fener-$VERSION.zip"

FENER_UNIVERSAL=1 FENER_RELEASE=1 scripts/build-app.sh
rm -rf "$DIST"; mkdir -p "$DIST"

# Notarize a zip of the app, staple the ticket to the app, then zip the stapled app.
ditto -c -k --keepParent .build/fener.app "$DIST/submit.zip"
xcrun notarytool submit "$DIST/submit.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple .build/fener.app
rm "$DIST/submit.zip"
ditto -c -k --keepParent .build/fener.app "$ZIP"

spctl --assess --type execute --verbose .build/fener.app
(cd "$DIST" && shasum -a 256 "fener-$VERSION.zip" > "fener-$VERSION.zip.sha256")
# The Homebrew cask for this release, for the omerdikyol/homebrew-tap repository (Casks/fener.rb).
SHA=$(cut -d' ' -f1 "$ZIP.sha256")
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/homebrew/fener.rb.in > "$DIST/fener.rb"
echo "release: $ZIP"
cat "$ZIP.sha256"
echo "cask:    $DIST/fener.rb"
