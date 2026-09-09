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

# Prompt with a 1 / 2 selection. Returns 0 for option 1, 1 for option 2.
# Usage: ui_ask "question" ["note"] ["option 1"] ["option 2"]
ui_ask() {
    _prompt="$1"
    _note="${2:-}"
    _opt1="${3:-Continue}"
    _opt2="${4:-Skip}"
    printf '\n       %s?%s  %s\n' "$C_CYAN" "$C_RESET" "$_prompt"
    if [ -n "$_note" ]; then
        ui_note "$_note"
    fi
    printf '\n'
    printf '          %s1%s  %s\n' "$C_BOLD" "$C_RESET" "$_opt1"
    printf '          %s2%s  %s\n' "$C_BOLD" "$C_RESET" "$_opt2"
    if [ ! -t 0 ]; then
        ui_info "no tty — choosing 1"
        return 0
    fi
    while true; do
        printf '          %sChoice [1]%s  ' "$C_DIM" "$C_RESET"
        read -r _reply || _reply=""
        case "$_reply" in
            ""|1) return 0 ;;
            2)    return 1 ;;
            *)    ui_note "type 1 or 2" ;;
        esac
    done
}

ui_done() {
    printf '\n'
    printf '  %s✓  Done.%s  Loading a login zsh with your aliases and path.\n' "$C_GREEN" "$C_RESET"
    printf '\n'
}
