#!/bin/bash
# Fresh Mac setup: Xcode CLT → Homebrew → chezmoi+age → apply everything.
# Usage: git clone <repo> ~/Developer/Dotfiles && ~/Developer/Dotfiles/bootstrap.sh
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    read -r -p "Press Enter once the Xcode CLT installation has finished..."
fi

echo "==> Homebrew"
if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> chezmoi, age, git"
brew install chezmoi age git

echo "==> age private key"
if [ ! -f "$HOME/.config/chezmoi/key.txt" ]; then
    mkdir -p "$HOME/.config/chezmoi"
    echo "Restore your age private key to: ~/.config/chezmoi/key.txt"
    echo "(keep it in your password manager; without it, encrypted secrets cannot be applied)"
    read -r -p "Press Enter once the key is in place..."
    chmod 600 "$HOME/.config/chezmoi/key.txt"
fi

echo "==> Applying dotfiles (this also installs all Brewfile packages)"
chezmoi init --apply --source "$DOTFILES_DIR"

echo ""
echo "Done. Restart your terminal to pick up the new shell setup."
