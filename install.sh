#!/bin/bash
# Fresh-Mac entry point. If the repo is public, run remotely:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)"
# Otherwise clone manually and run bootstrap.sh directly.
set -e

DOTFILES_DIR="$HOME/Developer/Dotfiles"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "==> Installing Xcode Command Line Tools"
    xcode-select --install
    read -r -p "Press Enter once the installation has finished..."
fi

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "==> Cloning dotfiles"
    mkdir -p "$HOME/Developer"
    git clone https://github.com/alexiscreuzot/Dotfiles.git "$DOTFILES_DIR"
fi

exec "$DOTFILES_DIR/bootstrap.sh"
