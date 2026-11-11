#!/bin/sh
# Packs the notarized .build/fener.app into .build/dist/fener-<version>.dmg: the app next to an
# Applications shortcut, with fener's icon on the disk. The DMG is signed with the Developer
# ID, notarized and stapled, so it opens without a warning. Run by release.sh after the app
# is notarized; it can also be run on its own.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
PROFILE=${FENER_NOTARY_PROFILE:-fener-notary}
APP=.build/fener.app
DMG=.build/dist/fener-$(cat VERSION).dmg
STAGE=.build/dmg

xcrun stapler validate "$APP" >/dev/null || { echo "make-dmg: $APP is not notarized; run scripts/release.sh" >&2; exit 1; }
identity=${FENER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep '"Developer ID Application:' | head -1 | awk '{print $2}')}
[ -n "$identity" ] || { echo "make-dmg: needs a Developer ID Application certificate" >&2; exit 1; }

rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE" .build/dist
ditto "$APP" "$STAGE/fener.app"
ln -s /Applications "$STAGE/Applications"
cp assets/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# A writable image first, to mark the volume icon, then the compressed read-only one.
rw=.build/fener-rw.dmg; rm -f "$rw"
hdiutil create -quiet -volname "fener" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$rw"
mnt=$(hdiutil attach -nobrowse -noautoopen "$rw" | awk -F'\t' '/\/Volumes\// {print $NF}')
SetFile -a C "$mnt"
hdiutil detach -quiet "$mnt"
hdiutil convert -quiet "$rw" -format ULFO -o "$DMG"
rm -f "$rw"; rm -rf "$STAGE"

codesign --force --timestamp --sign "$identity" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
(cd .build/dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "dmg: $DMG (fener $VERSION)"
