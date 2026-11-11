#!/bin/sh
# Publishes a new version of fener:
#   1. sets VERSION, commits and pushes it
#   2. builds the notarized app (scripts/release.sh)
#   3. creates the GitHub release vX.Y.Z with the zip and its SHA-256
#   4. updates the Homebrew cask in the tap and pushes it
#
#   scripts/publish.sh 0.2.0 [--notes notes.md] [--dry-run]
#
# Without --notes, GitHub writes the notes from the commits since the last release.
# --dry-run runs the checks and prints the steps without changing anything.
# The tap is ../homebrew-tap (FENER_TAP_DIR to change it), cloned there if missing.
set -eu
cd "$(dirname "$0")/.."

REPO=omerdikyol/fener
TAP_REPO=omerdikyol/homebrew-tap
TAP_DIR=${FENER_TAP_DIR:-../homebrew-tap}

version="" notes="" dry=0
while [ $# -gt 0 ]; do
    case "$1" in
        --notes) notes=$2; shift 2 ;;
        --dry-run) dry=1; shift ;;
        -*) echo "unknown option $1" >&2; exit 2 ;;
        *) version=$1; shift ;;
    esac
done
fail() { echo "publish: $*" >&2; exit 1; }
run() { if [ $dry = 1 ]; then echo "  would run: $*"; else "$@"; fi; }

# ---- checks, before anything changes ----
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "usage: scripts/publish.sh X.Y.Z [--notes file] [--dry-run]"
[ -z "$notes" ] || [ -f "$notes" ] || fail "no notes file $notes"
[ "$(git branch --show-current)" = main ] || fail "not on main"
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main differs from origin/main; pull or push first"
! git ls-remote --exit-code --tags origin "v$version" >/dev/null 2>&1 || fail "tag v$version already exists on GitHub"
current=$(cat VERSION)
[ "$version" != "$current" ] || fail "VERSION is already $version"
xcrun notarytool history --keychain-profile "${FENER_NOTARY_PROFILE:-fener-notary}" >/dev/null 2>&1 || fail "no notary credentials (see scripts/release.sh)"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in"
echo "publishing fener $current -> $version"

# ---- 1. version ----
if [ $dry = 0 ]; then
    echo "$version" > VERSION
    git commit -qm "fener $version" VERSION
    git push -q origin main
else
    echo "  would set VERSION to $version, commit and push"
fi

# ---- 2. build ----
run scripts/release.sh
zip=".build/dist/fener-$version.zip"

# ---- 3. GitHub release ----
if [ $dry = 0 ]; then
    printf 'Publish fener %s to GitHub and Homebrew now? [y/N] ' "$version"
    read -r answer
    [ "$answer" = y ] || [ "$answer" = Y ] || fail "stopped before publishing; VERSION is committed, the build is in .build/dist"
fi
if [ -n "$notes" ]; then notes_args="--notes-file $notes"; else notes_args="--generate-notes"; fi
# shellcheck disable=SC2086
run gh release create "v$version" --repo "$REPO" --target main --title "fener $version" $notes_args "$zip" "$zip.sha256"

# ---- 4. Homebrew tap ----
if [ ! -d "$TAP_DIR/.git" ]; then run gh repo clone "$TAP_REPO" "$TAP_DIR"; fi
run cp .build/dist/fener.rb "$TAP_DIR/Casks/fener.rb"
run git -C "$TAP_DIR" commit -qm "fener $version" Casks/fener.rb
run git -C "$TAP_DIR" push -q origin main

echo "published fener $version"
echo "  release: https://github.com/$REPO/releases/tag/v$version"
echo "  brew:    brew upgrade --cask omerdikyol/tap/fener"
