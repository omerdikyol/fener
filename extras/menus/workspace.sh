#!/bin/sh
# Executable menu: every OmniWM workspace with its window count and apps, the current one
# marked. Choosing one switches to it. Uses jq when installed, plutil otherwise.
WM=$(command -v omniwmctl) || { [ $# -eq 0 ] && echo '{"name": "omniwmctl not found", "icon": "nf-md-alert"}'; exit 0; }
[ $# -gt 0 ] && exec "$WM" command switch-workspace "$1"

# Fast path with jq (two calls); the plutil loop below works everywhere but is slower.
if command -v jq >/dev/null; then
    "$WM" query windows --format json | jq -r '.result.payload.windows[] | "\(.workspace.number)\t\(.app.name)"' > /tmp/fener-ws-apps.$$
    "$WM" query workspaces --format json | jq -r --rawfile apps /tmp/fener-ws-apps.$$ '
      ($apps | split("\n") | map(select(length > 0) | split("\t"))) as $a
      | .result.payload.workspaces[]
      | . as $w
      | ([$a[] | select(.[0] == ($w.number | tostring)) | .[1]] | unique | join(", ")) as $names
      | (if $w.counts.total == 0 then "empty" elif $w.counts.total == 1 then "1 window" else "\($w.counts.total) windows" end) as $count
      | {name: "Workspace \($w.number)",
         subtitle: ((if $w.isCurrent then "current · " else "" end) + $count + (if $names == "" then "" else " · " + $names end)),
         value: "\($w.number)", icon: "nf-md-numeric_\($w.number)_box"} | tojson'
    rm -f /tmp/fener-ws-apps.$$
    exit 0
fi

tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
"$WM" query workspaces --format json > "$tmp/ws.json" || exit 1
"$WM" query windows --format json > "$tmp/win.json" || exit 1
get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# "number<TAB>app" for every window, to list each workspace's apps.
nw=$(get "$tmp/win.json" result.payload.windows)
i=0; while [ "$i" -lt "${nw:-0}" ]; do
    printf '%s\t%s\n' "$(get "$tmp/win.json" result.payload.windows.$i.workspace.number)" \
                      "$(get "$tmp/win.json" result.payload.windows.$i.app.name)"
    i=$((i + 1))
done > "$tmp/apps.tsv"

n=$(get "$tmp/ws.json" result.payload.workspaces)
i=0; while [ "$i" -lt "${n:-0}" ]; do
    num=$(get "$tmp/ws.json" result.payload.workspaces.$i.number)
    total=$(get "$tmp/ws.json" result.payload.workspaces.$i.counts.total)
    cur=$(get "$tmp/ws.json" result.payload.workspaces.$i.isCurrent)
    apps=$(awk -F'\t' -v n="$num" '$1 == n { print $2 }' "$tmp/apps.tsv" | sort -u | paste -sd ',' - | sed 's/,/, /g')
    case "${total:-0}" in 0) sub="empty" ;; 1) sub="1 window" ;; *) sub="$total windows" ;; esac
    [ -n "$apps" ] && sub="$sub · $apps"
    [ "$cur" = true ] && sub="current · $sub"
    printf '{"name": "Workspace %s", "subtitle": "%s", "value": "%s", "icon": "nf-md-numeric_%s_box"}\n' "$num" "$sub" "$num" "$num"
    i=$((i + 1))
done
