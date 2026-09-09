#!/bin/bash
# Fresh-Mac entry point:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)"
set -e

DOTFILES_DIR="$HOME/Developer/Dotfiles"
REPO_SSH="git@github.com:alexiscreuzot/Dotfiles.git"

github_ssh_ok() {
    ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 \
        | grep -q "successfully authenticated"
}

ensure_ssh_key() {
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        return
    fi
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "alexis.creuzot@gmail.com"
}

echo "==> Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    read -r -p "Press Enter once the installation has finished..."
fi

echo "==> Homebrew"
if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

echo "==> git, gh, chezmoi, age"
brew install git gh chezmoi age

echo "==> Bitwarden"
brew install --cask bitwarden
open -a Bitwarden
echo ""
echo "Sign in to Bitwarden, then enable its Safari extension:"
echo "  Safari → Settings → Extensions → Bitwarden"
echo ""
read -r -p "Press Enter once Bitwarden is signed in and the Safari extension is enabled..."

echo "==> GitHub SSH"
if ! github_ssh_ok; then
    echo "Opening Safari to authenticate with GitHub (Bitwarden can fill the login)."
    BROWSER=safari gh auth login \
        --hostname github.com \
        --git-protocol ssh \
        --web \
        --scopes admin:public_key
fi

if ! github_ssh_ok; then
    ensure_ssh_key
    pbcopy < "$HOME/.ssh/id_ed25519.pub"
    echo ""
    echo "SSH still isn't working. The public key is on your clipboard:"
    echo ""
    cat "$HOME/.ssh/id_ed25519.pub"
    echo ""
    echo "Safari will open the GitHub SSH key form — paste and save, then come back."
    open -a Safari "https://github.com/settings/ssh/new"
    read -r -p "Press Enter once the key is added..."
fi

if ! github_ssh_ok; then
    echo "GitHub SSH authentication still failed. Add the key at https://github.com/settings/keys and re-run."
    exit 1
fi

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "==> Cloning dotfiles"
    mkdir -p "$HOME/Developer"
    git clone "$REPO_SSH" "$DOTFILES_DIR"
fi

exec "$DOTFILES_DIR/bootstrap.sh"
