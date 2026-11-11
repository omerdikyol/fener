#!/bin/sh
# Builds assets/AppIcon.icns from assets/icon-1024.png (made by scripts/make-icon.swift).
set -eu
cd "$(dirname "$0")/.."
set_dir=.build/AppIcon.iconset
rm -rf "$set_dir"; mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
    sips -z $s $s assets/icon-1024.png --out "$set_dir/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) assets/icon-1024.png --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o assets/AppIcon.icns
echo "wrote assets/AppIcon.icns"
