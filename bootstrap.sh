#!/bin/bash
# Post-clone apply. Run install.sh on a fresh Mac; this script is invoked from there.
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -z "${DOTFILES_FROM_INSTALL:-}" ]; then
    DOTFILES_STEPS=2
    DOTFILES_STEP=0
fi

# shellcheck source=ui.sh
. "$DOTFILES_DIR/ui.sh"

load_brew() {
    if command -v brew >/dev/null 2>&1; then
        eval "$(brew shellenv)"
        return 0
    fi
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        return 0
    fi
    if [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        return 0
    fi
    return 1
}

load_brew || true

_missing=""
for cmd in brew chezmoi age git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        _missing="$_missing $cmd"
    fi
done
if [ -n "$_missing" ]; then
    ui_header
    ui_fail "missing tools:$_missing"
    ui_note "run install.sh first — it will skip anything you already have"
    ui_note "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)\""
    exit 1
fi

if [ -z "${DOTFILES_FROM_INSTALL:-}" ]; then
    ui_header
fi

ui_step "age private key"
_key="$HOME/.config/chezmoi/key.txt"
if [ -s "$_key" ]; then
    ui_ok "already in place  $_key"
else
    mkdir -p "$HOME/.config/chezmoi"
    ui_info "encrypted secrets need your age key from Bitwarden"
    ui_note "item looks like AGE-SECRET-KEY-..."
    ui_note "paste it into  $_key"
    if ui_ask "Have you saved the age key into that file?"; then
        if [ -s "$_key" ]; then
            chmod 600 "$_key"
            ui_ok "key is in place"
        else
            ui_warn "file is still missing or empty — encrypted files will be skipped"
        fi
    else
        ui_info "skipped — encrypted secrets won't apply until the key is there"
    fi
    if [ -f "$_key" ]; then
        chmod 600 "$_key"
    fi
fi

ui_step "Apply"
ui_info "chezmoi writes configs, then brew bundle, oh-my-zsh, and macOS defaults"
if chezmoi source-path >/dev/null 2>&1; then
    ui_info "chezmoi already initialized — applying"
    if chezmoi apply --source "$DOTFILES_DIR"; then
        ui_ok "applied"
    else
        ui_warn "apply reported errors — already-installed apps are usually why"
        ui_note "re-run anytime; finished work is skipped"
    fi
else
    ui_info "first apply — this can take a while"
    if chezmoi init --apply --source "$DOTFILES_DIR"; then
        ui_ok "applied"
    else
        ui_warn "apply reported errors — already-installed apps are usually why"
        ui_note "re-run anytime; finished work is skipped"
    fi
fi

ui_done
