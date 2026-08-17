#!/bin/bash

if [ -d "$HOME/.oh-my-zsh" ]; then
    exit 0
fi

# KEEP_ZSHRC: don't clobber the chezmoi-managed .zshrc
RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
