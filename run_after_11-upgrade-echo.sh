#!/bin/bash
# Upgrade Echo to the latest cask on every apply. brew bundle only
# installs missing formulae; it will not pick up new Echo releases.

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found, skipping echo"
    exit 0
fi

_tap="alexiscreuzot/echo"
_cask="alexiscreuzot/echo/echo"
_repo="$(brew --repo "$_tap" 2>/dev/null || true)"

if [ -d "$_repo/.git" ]; then
    git -C "$_repo" pull --ff-only --quiet || \
        echo "warning: could not update $_tap"
else
    brew tap "$_tap" "https://github.com/alexiscreuzot/echo" || {
        echo "warning: could not tap $_tap"
        exit 0
    }
fi

if brew list --cask echo >/dev/null 2>&1; then
    brew upgrade --cask "$_cask" || \
        echo "warning: echo upgrade failed — see output above"
else
    brew install --cask "$_cask" || \
        echo "warning: echo install failed — see output above"
fi
