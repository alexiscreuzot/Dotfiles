#!/bin/bash
# Install what a Brewfile lists and nothing more. Used by both repos.
# Usage: brew-bundle.sh <Brewfile>
set -u

_brewfile="${1:-}"
if [ -z "$_brewfile" ] || [ ! -f "$_brewfile" ]; then
    echo "usage: brew-bundle.sh <Brewfile>" >&2
    exit 1
fi

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found, skipping brew bundle"
    exit 0
fi

# Homebrew resets the sudo timestamp on every `brew` call. SUDO_ASKPASS
# (set by keep_sudo) is how later pkg casks get the password without a prompt.
if [ -n "${SUDO_ASKPASS:-}" ] && [ -x "$SUDO_ASKPASS" ]; then
    sudo -A -v 2>/dev/null || true
fi

# Tap first so brew info can see tap casks.
while read -r _tap _url; do
    [ -n "$_tap" ] || continue
    if [ -n "$_url" ]; then
        brew tap "$_tap" "$_url" >/dev/null 2>&1 || true
    else
        brew tap "$_tap" >/dev/null 2>&1 || true
    fi
done <<EOF
$(awk -F'"' '/^tap / { print $2, $4 }' "$_brewfile")
EOF

# GUI apps declined at first run. chezmoi init --prompt to change that.
_cfg="$HOME/.config/chezmoi/chezmoi.toml"
if [ -f "$_cfg" ] && grep -Eq '^[[:space:]]*apps[[:space:]]*=[[:space:]]*false' "$_cfg"; then
    while IFS= read -r _cask; do
        [ -n "$_cask" ] || continue
        HOMEBREW_BUNDLE_CASK_SKIP="${HOMEBREW_BUNDLE_CASK_SKIP:+$HOMEBREW_BUNDLE_CASK_SKIP }$_cask"
    done <<EOF
$(awk '$1 == "cask" { name = $2; gsub(/"/, "", name); sub(/,.*/, "", name); n = split(name, a, "/"); print a[n] }' "$_brewfile")
EOF
    export HOMEBREW_BUNDLE_CASK_SKIP
    echo "skipping GUI apps"
fi

# Skip casks whose app, payload, or leftover helper is already on disk.
# brew bundle would otherwise try to reinstall them (and hang on pkg
# installers).
if [ -f "$_here/cask-present.py" ]; then
    _skip="$(python3 "$_here/cask-present.py" --skip --brewfile "$_brewfile" || true)"
    if [ -n "$_skip" ]; then
        HOMEBREW_BUNDLE_CASK_SKIP="${HOMEBREW_BUNDLE_CASK_SKIP:+$HOMEBREW_BUNDLE_CASK_SKIP }$_skip"
        export HOMEBREW_BUNDLE_CASK_SKIP
        echo "already installed, skipping: $_skip"
    fi
fi

# Homebrew 7 upgrades by default. That batches upgrades after the last
# "Using" line, then hangs on pkg installers or on quitting apps that
# are still open. Apply only installs what's missing.
brew bundle --no-upgrade --file="$_brewfile" || \
    echo "warning: some Brewfile entries failed — see output above"
