#!/bin/sh
# Executable menu: lists fener themes (built-in tokyo-night plus ~/.config/fener/themes/*.toml)
# and sets the chosen one in config.toml; fener applies it on save.
DIR="$HOME/.config/fener"
CFG="$DIR/config.toml"
current=$(sed -n 's/^theme *= *"\(.*\)".*/\1/p' "$CFG" 2>/dev/null)
current=${current:-tokyo-night}

if [ $# -eq 0 ]; then
    { echo tokyo-night; ls "$DIR/themes" 2>/dev/null | sed -n 's/\.toml$//p'; } | sort -u | while read -r t; do
        if [ "$t" = "$current" ]; then printf '{"name": "%s", "subtitle": "current"}\n' "$t"
        else printf '{"name": "%s"}\n' "$t"; fi
    done
    exit 0
fi

mkdir -p "$DIR"
if grep -q '^theme *=' "$CFG" 2>/dev/null; then
    sed -i '' "s/^theme *=.*/theme = \"$1\"/" "$CFG"
else  # top-level keys must come before any [table], so prepend
    { printf 'theme = "%s"\n' "$1"; cat "$CFG" 2>/dev/null; } > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi
