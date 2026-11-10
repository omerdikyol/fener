#!/bin/sh
# Executable menu: network speed with macOS's own networkQuality, run in the background.
# Opening the menu starts a test (unless one finished in the last minute); it shows the
# latest result and the average of the last 20. History keeps only date, download, upload
# and responsiveness, in ~/Library/Caches/fener/speedtest (never the server, interface or IP).
DIR="$HOME/Library/Caches/fener/speedtest"
HIST="$DIR/history.tsv"     # epoch <TAB> download bit/s <TAB> upload bit/s <TAB> responsiveness RPM
PID="$DIR/running.pid"
mkdir -p "$DIR"

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }

start() {
    running && return
    (
        out="$DIR/run.json"
        if networkQuality -c -M 15 > "$out" 2>/dev/null; then
            dl=$(plutil -extract dl_throughput raw -o - "$out" 2>/dev/null)
            ul=$(plutil -extract ul_throughput raw -o - "$out" 2>/dev/null)
            rpm=$(plutil -extract responsiveness raw -o - "$out" 2>/dev/null)
            [ -n "$dl" ] && printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$dl" "$ul" "${rpm:-0}" >> "$HIST"
        fi
        rm -f "$out" "$PID"
    ) </dev/null >/dev/null 2>&1 &
    echo $! > "$PID"
}

if [ "$1" = "run" ]; then start; exit 0; fi
[ $# -gt 0 ] && exit 0

# Start a fresh test when the menu opens, but not again right after one finished.
last=$(tail -n 1 "$HIST" 2>/dev/null | cut -f1)
[ -z "$last" ] || [ $(( $(date +%s) - last )) -gt 60 ] && start

mbps() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1e6 }'; }

if running; then
    printf '{"name": "Testing…", "subtitle": "about 15 s", "icon": "gauge.with.dots.needle.33percent"}\n'
    printf '{"refresh": 1}\n'
fi

if [ -s "$HIST" ]; then
    set -- $(tail -n 1 "$HIST")
    ago=$(( ($(date +%s) - $1) / 60 ))
    [ $ago -lt 1 ] && when="just now" || when="$ago min ago"
    printf '{"name": "↓ %s  ↑ %s Mbps", "subtitle": "%s", "value": "run", "icon": "gauge.with.dots.needle.67percent"}\n' \
        "$(mbps "$2")" "$(mbps "$3")" "$when"
    tail -n 20 "$HIST" | awk -F'\t' '{ d += $2; u += $3; n++ }
        END { printf "{\"name\": \"avg ↓ %.1f  ↑ %.1f Mbps\", \"subtitle\": \"%d test%s\", \"value\": \"run\", \"icon\": \"chart.bar\"}\n", d / n / 1e6, u / n / 1e6, n, (n == 1 ? "" : "s") }'
elif ! running; then
    printf '{"name": "Run a speed test", "value": "run", "icon": "gauge.with.dots.needle.67percent"}\n'
fi
