#!/bin/bash
# Post-clone apply. Run install.sh on a fresh Mac; this script is invoked from there.
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for cmd in brew chezmoi age git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing $cmd. Run install.sh first:"
        echo "  sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)\""
        exit 1
    fi
done

echo "==> age private key"
if [ ! -f "$HOME/.config/chezmoi/key.txt" ]; then
    mkdir -p "$HOME/.config/chezmoi"
    echo "Open Bitwarden, sign in, and copy your age secret key (AGE-SECRET-KEY-...)"
    echo "into: ~/.config/chezmoi/key.txt"
    echo "(without it, encrypted secrets cannot be applied)"
    read -r -p "Press Enter once the key is in place..."
    chmod 600 "$HOME/.config/chezmoi/key.txt"
fi

echo "==> Applying dotfiles (this also installs all Brewfile packages)"
chezmoi init --apply --source "$DOTFILES_DIR"

echo ""
echo "Done. Restart your terminal to pick up the new shell setup."
