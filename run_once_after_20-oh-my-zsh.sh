#!/bin/bash

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    # KEEP_ZSHRC: don't clobber the chezmoi-managed .zshrc
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if command -v brew >/dev/null 2>&1; then
    spaceship="$(brew --prefix)/opt/spaceship/spaceship.zsh-theme"
    if [ -f "$spaceship" ]; then
        mkdir -p "$HOME/.oh-my-zsh/custom/themes"
        ln -sfn "$spaceship" "$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme"
    fi
fi
