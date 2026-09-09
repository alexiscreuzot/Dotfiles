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

# Prompt on a tty. Returns 0 on continue / yes, 1 on skip / no.
# Default is continue (Enter). "s" or "n" skips.
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

ui_done() {
    printf '\n'
    printf '  %s✓  Done.%s  Loading a login zsh with your aliases and path.\n' "$C_GREEN" "$C_RESET"
    printf '\n'
}
