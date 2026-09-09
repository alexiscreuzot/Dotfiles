#!/bin/bash
# Post-clone apply. Run install.sh on a fresh Mac; this script is invoked from there.
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -z "${DOTFILES_FROM_INSTALL:-}" ]; then
    DOTFILES_STEPS=3
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
    if ui_ask "Have you saved the age key into that file?" "" \
        "It's saved" "Skip for now"; then
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

ui_step "Shell"
ui_info "making sure ~/.zshrc, oh-my-zsh, and aliases are in place"

if chezmoi apply --source "$DOTFILES_DIR" "$HOME/.zshrc"; then
    ui_ok "~/.zshrc  applied"
else
    ui_warn "chezmoi could not write ~/.zshrc — checking what's there"
fi

if [ -f "$HOME/.zshrc" ]; then
    ui_ok "~/.zshrc  present"
else
    ui_fail "~/.zshrc is missing — aliases will not load"
fi

_frag_ok=1
for _frag in path aliases functions; do
    if [ -f "$DOTFILES_DIR/$_frag" ]; then
        ui_ok "$_frag  $DOTFILES_DIR/$_frag"
    else
        ui_fail "$_frag  missing from $DOTFILES_DIR"
        _frag_ok=0
    fi
done

bash "$DOTFILES_DIR/run_once_after_20-oh-my-zsh.sh" || true
if [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    ui_ok "oh-my-zsh  installed"
else
    ui_warn "oh-my-zsh is not installed yet"
fi
if [ -L "$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme" ] || \
   [ -f "$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme" ]; then
    ui_ok "Spaceship theme  linked"
else
    ui_warn "Spaceship theme is not linked — prompt will fall back"
fi

_login_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$_login_shell" = "/bin/zsh" ] || [ "$_login_shell" = "/usr/local/bin/zsh" ] || \
   [ "$_login_shell" = "/opt/homebrew/bin/zsh" ]; then
    ui_ok "login shell  $_login_shell"
else
    ui_info "login shell is ${_login_shell:-unknown} — switching to /bin/zsh"
    if chsh -s /bin/zsh; then
        ui_ok "login shell  /bin/zsh"
    else
        ui_warn "could not change login shell — you can run:  chsh -s /bin/zsh"
    fi
fi

if [ "$_frag_ok" -eq 1 ] && [ -f "$HOME/.zshrc" ]; then
    if zsh -c 'source "$HOME/.zshrc" >/dev/null 2>&1 && alias g' >/dev/null 2>&1; then
        ui_ok "aliases load  g → git"
    else
        ui_warn "could not pre-check aliases — they should still load in the new shell"
    fi
fi

_zsh="$(command -v zsh || true)"
[ -x "$_zsh" ] || _zsh="/bin/zsh"

ui_done
if [ -t 0 ] && [ -x "$_zsh" ]; then
    exec "$_zsh" -l
fi
ui_note "no tty — in your next terminal, run:  source ~/.zshrc"
