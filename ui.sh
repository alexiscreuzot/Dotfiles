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
        _key=""
        IFS= read -r -s -n 1 _key < /dev/tty || _key=""
        if [ "$_key" = "$(printf '\033')" ]; then
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
        elif [ -z "$_key" ] || [ "$_key" = "$(printf '\n')" ] || [ "$_key" = "$(printf '\r')" ]; then
            printf '\033[?25h' >/dev/tty
            trap - INT
            UI_CHOICE=$UI_SEL
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
