#!/bin/sh
# Executable menu: `fener show wallpaper`.
# Run with no arguments it prints one JSON entry per line; fener runs it again with the
# chosen entry's "value" as $1 (also in $FENER_CHOICE).
DIR="$HOME/Pictures/Wallpapers"

if [ $# -eq 0 ]; then
    for f in "$DIR"/*.jpg "$DIR"/*.jpeg "$DIR"/*.png "$DIR"/*.heic; do
        [ -f "$f" ] || continue
        name=$(basename "$f"); name=${name%.*}
        # ponytail: no JSON escaping; file names with " or \ break that line.
        printf '{"name": "%s", "value": "%s", "icon": "%s"}\n' "$name" "$f" "$f"
    done
    exit 0
fi

osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$1\""
