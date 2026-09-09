#!/bin/bash
# Fresh-Mac entry point:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)"
set -e

DOTFILES_DIR="$HOME/Developer/Dotfiles"
REPO_SSH="git@github.com:alexiscreuzot/Dotfiles.git"
DOTFILES_STEPS=8
DOTFILES_STEP=0

# --- UI (keep in sync with ui.sh; inlined so a curled copy still looks right) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET="$(printf '\033[0m')"
    C_BOLD="$(printf '\033[1m')"
    C_DIM="$(printf '\033[2m')"
    C_RED="$(printf '\033[31m')"
    C_GREEN="$(printf '\033[32m')"
    C_YELLOW="$(printf '\033[33m')"
    C_CYAN="$(printf '\033[36m')"
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
fi

ui_header() {
    printf '\n'
    printf '  %sdotfiles%s\n' "$C_BOLD" "$C_RESET"
    printf '  %sfrom a clean Mac to a working one · already-done steps are skipped%s\n' "$C_DIM" "$C_RESET"
    printf '\n'
}

ui_step() {
    DOTFILES_STEP=$(( ${DOTFILES_STEP:-0} + 1 ))
    printf '\n'
    printf '  %s───%s  %s%s/%s%s  %s%s%s\n' \
        "$C_DIM" "$C_RESET" \
        "$C_BOLD" "$DOTFILES_STEP" "$DOTFILES_STEPS" "$C_RESET" \
        "$C_BOLD" "$1" "$C_RESET"
}

ui_ok()   { printf '       %s✓%s  %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
ui_info() { printf '       %s·%s  %s\n' "$C_DIM"    "$C_RESET" "$1"; }
ui_warn() { printf '       %s!%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
ui_fail() { printf '       %s✗%s  %s\n' "$C_RED"    "$C_RESET" "$1"; }

ui_note() {
    printf '          %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

ui_ask() {
    _prompt="$1"
    printf '\n       %s?%s  %s\n' "$C_CYAN" "$C_RESET" "$_prompt"
    if [ -n "${2:-}" ]; then
        ui_note "$2"
    fi
    if [ ! -t 0 ]; then
        ui_info "no tty — continuing"
        return 0
    fi
    printf '          %sEnter to continue · s to skip%s  ' "$C_DIM" "$C_RESET"
    read -r _reply || _reply=""
    case "$_reply" in
        [sSnN]*) return 1 ;;
        *)       return 0 ;;
    esac
}

# --- helpers ---

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

formula_ok() {
    brew list --formula "$1" >/dev/null 2>&1
}

cask_ok() {
    brew list --cask "$1" >/dev/null 2>&1
}

app_ok() {
    [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]
}

ensure_formula() {
    _name="$1"
    if formula_ok "$_name"; then
        ui_ok "$_name  already installed"
        return 0
    fi
    ui_info "installing $_name"
    if brew install --quiet "$_name"; then
        ui_ok "$_name  installed"
        return 0
    fi
    if formula_ok "$_name" || command -v "$_name" >/dev/null 2>&1; then
        ui_warn "$_name  brew reported an error, but it's present — continuing"
        return 0
    fi
    ui_fail "$_name  failed to install — continuing anyway"
    return 0
}

github_ssh_ok() {
    ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 \
        | grep -q "successfully authenticated"
}

ensure_ssh_key() {
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        ui_ok "SSH key already exists  ~/.ssh/id_ed25519"
        return 0
    fi
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "alexis.creuzot@gmail.com"
    ui_ok "created ~/.ssh/id_ed25519"
}

gh_logged_in() {
    command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1
}

# --- run ---

ui_header

ui_step "Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
    ui_ok "already installed  $(xcode-select -p)"
else
    ui_info "opening the installer"
    xcode-select --install || true
    ui_ask "Wait until the Command Line Tools installer finishes." || true
    if xcode-select -p >/dev/null 2>&1; then
        ui_ok "installed  $(xcode-select -p)"
    else
        ui_warn "not detected yet — later steps may prompt again"
    fi
fi

ui_step "Homebrew"
if load_brew; then
    ui_ok "already installed  $(command -v brew)"
else
    ui_info "installing Homebrew (its own installer will print next)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
    if load_brew; then
        ui_ok "installed  $(command -v brew)"
    else
        ui_fail "Homebrew is required. Re-run this script after it is installed."
        exit 1
    fi
fi

ui_step "CLI tools"
ensure_formula git
ensure_formula gh
ensure_formula chezmoi
ensure_formula age

ui_step "Bitwarden"
if app_ok Bitwarden || cask_ok bitwarden; then
    ui_ok "already installed"
else
    ui_info "installing Bitwarden"
    if brew install --cask --quiet bitwarden; then
        ui_ok "installed"
    elif app_ok Bitwarden; then
        ui_warn "brew reported an error, but Bitwarden.app is present — continuing"
    else
        ui_warn "Bitwarden failed to install — you can add it later from brew or the App Store"
    fi
fi

if github_ssh_ok; then
    ui_ok "GitHub SSH already works — skipping the Bitwarden sign-in pause"
elif app_ok Bitwarden; then
    open -a Bitwarden 2>/dev/null || true
    ui_ask \
        "Sign in to Bitwarden, then enable its Safari extension." \
        "Safari → Settings → Extensions → Bitwarden" || ui_info "skipped"
else
    ui_info "Bitwarden isn't available — GitHub login will be manual"
fi

ui_step "GitHub SSH"
if github_ssh_ok; then
    ui_ok "already authenticated"
else
    ensure_ssh_key
    if gh_logged_in; then
        ui_info "gh is already logged in — uploading this machine's key"
        _title="$(hostname -s 2>/dev/null || echo mac)-$(date +%Y-%m-%d)"
        if gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$_title" 2>/dev/null; then
            ui_ok "uploaded  $_title"
        else
            ui_info "key may already be on GitHub — that's fine"
        fi
    else
        ui_info "opening Safari for GitHub login (Bitwarden can fill it)"
        BROWSER=safari gh auth login \
            --hostname github.com \
            --git-protocol ssh \
            --web \
            --scopes admin:public_key || ui_warn "gh login didn't finish — trying the manual fallback"
    fi

    if github_ssh_ok; then
        ui_ok "authenticated"
    else
        ensure_ssh_key
        pbcopy < "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
        ui_warn "SSH still isn't working"
        ui_note "public key copied to the clipboard"
        ui_note "$(cat "$HOME/.ssh/id_ed25519.pub")"
        open -a Safari "https://github.com/settings/ssh/new" 2>/dev/null || \
            open "https://github.com/settings/ssh/new" 2>/dev/null || true
        ui_ask "Paste the key on the GitHub form, save, then come back." || true
        if github_ssh_ok; then
            ui_ok "authenticated"
        else
            ui_warn "GitHub SSH still failed — clone will be skipped if it needs auth"
            ui_note "add the key at https://github.com/settings/keys and re-run"
        fi
    fi
fi

ui_step "Clone"
if [ -d "$DOTFILES_DIR/.git" ]; then
    ui_ok "already cloned  $DOTFILES_DIR"
elif [ -d "$DOTFILES_DIR" ]; then
    ui_warn "$DOTFILES_DIR exists but is not a git repo"
    if [ -x "$DOTFILES_DIR/bootstrap.sh" ]; then
        ui_info "bootstrap.sh is there — continuing"
    else
        ui_fail "no bootstrap.sh in that folder — move it aside and re-run"
        exit 1
    fi
else
    mkdir -p "$HOME/Developer"
    if github_ssh_ok; then
        ui_info "cloning over SSH"
        if git clone "$REPO_SSH" "$DOTFILES_DIR"; then
            ui_ok "cloned  $DOTFILES_DIR"
        else
            ui_fail "clone failed"
            exit 1
        fi
    else
        ui_fail "can't clone without GitHub SSH"
        ui_note "fix auth, then re-run — this script will skip finished steps"
        exit 1
    fi
fi

export DOTFILES_STEPS DOTFILES_STEP DOTFILES_FROM_INSTALL=1
exec "$DOTFILES_DIR/bootstrap.sh"
