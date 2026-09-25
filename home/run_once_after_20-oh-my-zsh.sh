#!/bin/bash
# Install oh-my-zsh (once) and link the Homebrew Spaceship theme.

_omz="$HOME/.oh-my-zsh"

_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return
    fi
    if [ -n "${SUDO_ASKPASS:-}" ] && [ -x "$SUDO_ASKPASS" ]; then
        sudo -A "$@"
        return
    fi
    if [ -r /dev/tty ]; then
        sudo "$@" </dev/tty
        return
    fi
    sudo "$@"
}

# A previous sudo install leaves ~/.oh-my-zsh owned by root, so ln fails
# and chezmoi aborts the rest of apply.
_own_oh_my_zsh() {
    [ -d "$_omz" ] || return 0
    if [ "$(stat -f %u "$_omz" 2>/dev/null || echo 0)" -eq "$(id -u)" ]; then
        return 0
    fi
    echo "oh-my-zsh is not owned by $(id -un) — taking ownership"
    _sudo chown -R "$(id -u):$(id -g)" "$_omz"
}

if [ ! -d "$_omz" ]; then
    # KEEP_ZSHRC: don't clobber the chezmoi-managed .zshrc
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

_own_oh_my_zsh || true

if command -v brew >/dev/null 2>&1; then
    spaceship="$(brew --prefix)/opt/spaceship/spaceship.zsh-theme"
    if [ -f "$spaceship" ]; then
        mkdir -p "$_omz/custom/themes" 2>/dev/null || true
        if ! ln -sfn "$spaceship" "$_omz/custom/themes/spaceship.zsh-theme" 2>/dev/null; then
            echo "warning: could not link Spaceship theme"
        fi
    fi
fi
