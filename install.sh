#!/bin/bash
# Fresh-Mac entry point (quoted ?$(date +%s) busts GitHub's raw CDN cache;
# zsh treats an unquoted ? as a glob and errors with "no matches found"):
#   sh -c "$(curl -fsSL "https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh?$(date +%s)")"
set -e

DOTFILES_DIR="$HOME/Developer/alexiscreuzot/Dotfiles"
DOTFILES_LINK="$HOME/Developer/Dotfiles"
REPO_SSH="git@github.com:alexiscreuzot/Dotfiles.git"
DOTFILES_STEPS=9
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
    _note="${2:-}"
    _opt1="${3:-Continue}"
    _opt2="${4:-Skip}"
    _sel=1

    printf '\n       %s?%s  %s\n' "$C_CYAN" "$C_RESET" "$_prompt"
    if [ -n "$_note" ]; then
        ui_note "$_note"
    fi
    printf '\n'

    if [ ! -r /dev/tty ] || [ ! -t 1 ]; then
        ui_info "no tty — choosing 1"
        return 0
    fi

    _ui_menu_draw() {
        if [ "$_sel" -eq 1 ]; then
            printf '          %s▸ %s%s\n' "$C_BOLD$C_CYAN" "$_opt1" "$C_RESET"
        else
            printf '            %s%s%s\n' "$C_DIM" "$_opt1" "$C_RESET"
        fi
        if [ "$_sel" -eq 2 ]; then
            printf '          %s▸ %s%s\n' "$C_BOLD$C_CYAN" "$_opt2" "$C_RESET"
        else
            printf '            %s%s%s\n' "$C_DIM" "$_opt2" "$C_RESET"
        fi
        printf '          %s↑↓  move · Enter  confirm%s\n' "$C_DIM" "$C_RESET"
    }

    _ui_menu_draw
    printf '\033[?25l' >/dev/tty
    trap 'printf "\033[?25h" >/dev/tty' INT

    while true; do
        _ui_ch=""
        IFS= read -r -s -n 1 _ui_ch < /dev/tty || _ui_ch=""
        if [ "$_ui_ch" = "$(printf '\033')" ]; then
            _rest=""
            IFS= read -r -s -n 2 -t 1 _rest < /dev/tty || _rest=""
            case "$_rest" in
                "[A"|"[D") _sel=1 ;;
                "[B"|"[C") _sel=2 ;;
            esac
        elif [ -z "$_ui_ch" ] || [ "$_ui_ch" = "$(printf '\n')" ] || [ "$_ui_ch" = "$(printf '\r')" ]; then
            printf '\033[?25h' >/dev/tty
            trap - INT
            IFS= read -r -s -n 1 -t 0 _drain < /dev/tty || true
            if [ "$_sel" -eq 1 ]; then
                return 0
            fi
            return 1
        else
            continue
        fi
        printf '\033[3A'
        _ui_menu_draw
    done
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

unlock_ssh() {
    if [ -f "$HOME/.ssh/id_ed25519" ]; then
        ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || \
            ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
    fi
}

_ssh_github_hi() {
    printf '%s\n' "$1" | grep -q "successfully authenticated"
}

github_ssh_ok() {
    unlock_ssh
    _out="$(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 || true)"
    if _ssh_github_hi "$_out"; then
        return 0
    fi
    _out="$(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p 443 -T git@ssh.github.com 2>&1 || true)"
    _ssh_github_hi "$_out"
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
    ui_ask "Wait until the Command Line Tools installer finishes." "" \
        "It's finished" "Skip" || true
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

if github_ssh_ok || [ -d "$DOTFILES_DIR/.git" ]; then
    ui_ok "GitHub already set up — skipping the Bitwarden sign-in pause"
elif app_ok Bitwarden; then
    if ui_ask \
        "Sign in to Bitwarden, then enable its Safari extension (needed only if we open GitHub next)." \
        "Safari → Settings → Extensions → Bitwarden" \
        "Open Bitwarden" "Skip"; then
        open -a Bitwarden 2>/dev/null || true
    else
        ui_info "skipped"
    fi
else
    ui_info "Bitwarden isn't available — GitHub login will be manual if needed"
fi

ui_step "GitHub SSH"
if github_ssh_ok; then
    ui_ok "already authenticated"
elif [ -d "$DOTFILES_DIR/.git" ]; then
    ui_ok "repo is already on disk — skipping GitHub login"
    ui_note "SSH didn't confirm in this check; that's fine if you already added a key"
else
    if ! ui_ask \
        "This Mac isn't authenticated to GitHub over SSH yet." \
        "" \
        "Open Safari to log in" "Skip — I already have a key"; then
        ui_info "skipped — not opening GitHub"
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
                --scopes admin:public_key || ui_warn "gh login didn't finish"
        fi

        if ! github_ssh_ok; then
            ensure_ssh_key
            pbcopy < "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
            ui_warn "SSH still isn't confirmed"
            ui_note "public key copied to the clipboard"
            ui_note "$(cat "$HOME/.ssh/id_ed25519.pub")"
            if ui_ask "Open the GitHub SSH key form in Safari?" "" \
                "Open Safari" "Skip"; then
                open -a Safari "https://github.com/settings/ssh/new" 2>/dev/null || \
                    open "https://github.com/settings/ssh/new" 2>/dev/null || true
                ui_ask "Paste the key, save, then come back." "" \
                    "It's saved" "Skip" || true
            else
                ui_info "skipped — not opening GitHub"
            fi
        fi
    fi

    if github_ssh_ok; then
        ui_ok "authenticated"
    else
        ui_warn "GitHub SSH still not confirmed — clone will try anyway"
        ui_note "if it fails, add the key at https://github.com/settings/keys and re-run"
    fi
fi

ui_step "Clone"
mkdir -p "$HOME/Developer/alexiscreuzot"
if [ -d "$DOTFILES_DIR/.git" ]; then
    ui_ok "already cloned  $DOTFILES_DIR"
    ui_info "pulling latest"
    if git -C "$DOTFILES_DIR" pull --ff-only; then
        ui_ok "up to date"
    else
        ui_warn "pull didn't fast-forward — continuing with what's on disk"
    fi
elif [ -d "$DOTFILES_DIR" ]; then
    ui_warn "$DOTFILES_DIR exists but is not a git repo"
    if [ -x "$DOTFILES_DIR/bootstrap.sh" ]; then
        ui_info "bootstrap.sh is there — continuing"
    else
        ui_fail "no bootstrap.sh in that folder — move it aside and re-run"
        exit 1
    fi
else
    ui_info "cloning over SSH"
    if git clone "$REPO_SSH" "$DOTFILES_DIR"; then
        ui_ok "cloned  $DOTFILES_DIR"
    else
        ui_fail "clone failed"
        ui_note "add a key at https://github.com/settings/keys and re-run"
        exit 1
    fi
fi
if [ -L "$DOTFILES_LINK" ] || [ ! -e "$DOTFILES_LINK" ]; then
    ln -sfn alexiscreuzot/Dotfiles "$DOTFILES_LINK"
    ui_ok "link  $DOTFILES_LINK → alexiscreuzot/Dotfiles"
fi

export DOTFILES_STEPS DOTFILES_STEP DOTFILES_FROM_INSTALL=1
exec "$DOTFILES_DIR/bootstrap.sh"
