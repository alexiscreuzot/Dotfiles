# Shared terminal UI for install.sh and bootstrap.sh.
# install.sh inlines these so a curled copy still looks right.

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

DOTFILES_STEPS="${DOTFILES_STEPS:-8}"

# --- UI ---

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

# Unnumbered heading, for scripts that check rather than progress
ui_section() {
    printf '\n'
    printf '  %s───%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

ui_ok()   { printf '       %s✓%s  %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
ui_info() { printf '       %s·%s  %s\n' "$C_DIM"    "$C_RESET" "$1"; }
ui_warn() { printf '       %s!%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
ui_fail() { printf '       %s✗%s  %s\n' "$C_RED"    "$C_RESET" "$1"; }

ui_note() {
    printf '          %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

# Arrow-key menu. Sets UI_CHOICE to the 1-based index.
# Usage: ui_menu "question" "note" "option 1" ["option 2" ...]
ui_menu() {
    _prompt="$1"
    _note="$2"
    shift 2
    UI_N=0
    for _o in "$@"; do
        UI_N=$((UI_N + 1))
        eval "UI_OPT_${UI_N}=\"\$_o\""
    done
    UI_SEL=1
    UI_CHOICE=1

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
        _i=1
        while [ "$_i" -le "$UI_N" ]; do
            eval "_o=\$UI_OPT_${_i}"
            if [ "$_i" -eq "$UI_SEL" ]; then
                printf '          %s▸ %s%s\n' "$C_BOLD$C_CYAN" "$_o" "$C_RESET"
            else
                printf '            %s%s%s\n' "$C_DIM" "$_o" "$C_RESET"
            fi
            _i=$((_i + 1))
        done
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
                "[A"|"[D")
                    if [ "$UI_SEL" -gt 1 ]; then
                        UI_SEL=$((UI_SEL - 1))
                    else
                        UI_SEL=$UI_N
                    fi
                    ;;
                "[B"|"[C")
                    if [ "$UI_SEL" -lt "$UI_N" ]; then
                        UI_SEL=$((UI_SEL + 1))
                    else
                        UI_SEL=1
                    fi
                    ;;
            esac
        elif [ -z "$_ui_ch" ] || [ "$_ui_ch" = "$(printf '\n')" ] || [ "$_ui_ch" = "$(printf '\r')" ]; then
            printf '\033[?25h' >/dev/tty
            trap - INT
            UI_CHOICE=$UI_SEL
            # CR+LF leaves a leftover newline that the next read would swallow
            IFS= read -r -s -n 1 -t 0 _drain < /dev/tty || true
            return 0
        else
            continue
        fi
        printf '\033[%sA' $((UI_N + 1))
        _ui_menu_draw
    done
}

# Two-option wrapper. Returns 0 for option 1, 1 for option 2.
# Usage: ui_ask "question" ["note"] ["option 1"] ["option 2"]
ui_ask() {
    ui_menu "$1" "${2:-}" "${3:-Continue}" "${4:-Skip}"
    if [ "$UI_CHOICE" -eq 1 ]; then
        return 0
    fi
    return 1
}

ui_done() {
    printf '\n'
    printf '  %s✓  Done.%s  Loading a login zsh with your aliases and path.\n' "$C_GREEN" "$C_RESET"
    printf '\n'
}

# --- sudo ---

# Homebrew runs `sudo --reset-timestamp` on every `brew` invocation, so a
# normal sudo ticket never survives to brew bundle. Cache the password in a
# temp askpass instead; brew keeps SUDO_ASKPASS in its filtered environment.
keep_sudo() {
    if ! command -v sudo >/dev/null 2>&1 || [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if [ -n "${SUDO_ASKPASS:-}" ] && [ -x "$SUDO_ASKPASS" ]; then
        if sudo -A -v 2>/dev/null; then
            if [ -z "${DOTFILES_FROM_INSTALL:-}" ]; then
                ui_ok "Mac password already cached"
            fi
            return 0
        fi
    fi
    if [ ! -r /dev/tty ] || [ ! -t 1 ]; then
        ui_info "no tty — some installs may ask for a password later"
        return 0
    fi

    _sudo_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sudo.XXXXXX")"
    chmod 700 "$_sudo_dir"
    _sudo_pass="$_sudo_dir/pass"
    _sudo_ask="$_sudo_dir/askpass"
    _old_umask="$(umask)"
    umask 077
    : > "$_sudo_pass"
    printf '#!/bin/sh\nexec cat '\''%s'\''\n' "$_sudo_pass" > "$_sudo_ask"
    umask "$_old_umask"
    chmod 700 "$_sudo_ask"

    ui_info "enter your Mac password once — later installs reuse it"
    _ok=0
    _try=0
    while [ "$_try" -lt 2 ]; do
        printf '          Password: ' > /dev/tty
        _pw=""
        IFS= read -r -s _pw < /dev/tty || _pw=""
        printf '\n' > /dev/tty
        _try=$((_try + 1))
        if [ -z "$_pw" ]; then
            continue
        fi
        printf '%s\n' "$_pw" > "$_sudo_pass"
        unset _pw
        SUDO_ASKPASS="$_sudo_ask"
        export SUDO_ASKPASS
        if sudo -A -v 2>/dev/null; then
            _ok=1
            break
        fi
        ui_warn "incorrect password, try again"
        : > "$_sudo_pass"
        unset SUDO_ASKPASS
    done

    if [ "$_ok" -ne 1 ]; then
        rm -rf "$_sudo_dir"
        unset SUDO_ASKPASS
        ui_warn "sudo failed — some casks may ask again"
        return 0
    fi

    export SUDO_ASKPASS="$_sudo_ask"
    export DOTFILES_SUDO_DIR="$_sudo_dir"
    if [ -z "${DOTFILES_SUDO_TRAP:-}" ]; then
        trap 'stop_sudo_keepalive' EXIT
        export DOTFILES_SUDO_TRAP=1
    fi
    ui_ok "cached for this session"
}

stop_sudo_keepalive() {
    if [ -n "${DOTFILES_SUDO_DIR:-}" ]; then
        rm -rf "$DOTFILES_SUDO_DIR"
    fi
    unset DOTFILES_SUDO_DIR SUDO_ASKPASS
}

# Prefer the session askpass so brew's sudo --reset-timestamp doesn't prompt.
dotfiles_sudo() {
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

# Root-owned files in $HOME break later ln/mkdir.
reclaim_if_foreign() {
    _path="$1"
    [ -e "$_path" ] || return 0
    if [ "$(stat -f %u "$_path" 2>/dev/null || echo 0)" -eq "$(id -u)" ]; then
        return 0
    fi
    ui_info "taking ownership of $_path"
    if dotfiles_sudo chown -R "$(id -u):$(id -g)" "$_path"; then
        ui_ok "owned by $(id -un)  $_path"
    else
        ui_warn "could not take ownership of $_path"
    fi
}

# --- brew ---

# Add brew to PATH whether it is already on PATH or in a default prefix.
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
