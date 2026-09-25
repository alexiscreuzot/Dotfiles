#!/bin/bash
# Reports on a machine set up by install.sh / bootstrap.sh. Changes nothing.
set -u

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# shellcheck source=ui.sh
. "$DOTFILES_DIR/scripts/ui.sh"

load_brew || true

PASS=0
WARN=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    ui_ok "$1"
}

warn() {
    WARN=$((WARN + 1))
    ui_warn "$1"
    if [ -n "${2:-}" ]; then ui_note "$2"; fi
}

bad() {
    FAIL=$((FAIL + 1))
    ui_fail "$1"
    if [ -n "${2:-}" ]; then ui_note "$2"; fi
}

# Join non-empty arguments with two spaces.
join() {
    _s=""
    for _p in "$@"; do
        [ -n "$_p" ] || continue
        if [ -n "$_s" ]; then _s="$_s  $_p"; else _s="$_p"; fi
    done
    printf '%s' "$_s"
}

# Labelled name list, wrapping onto dim continuation lines.
emit_names() {
    _fn="$1"
    _label="$2"
    _body="${3:-}"
    [ -n "$_body" ] || return
    _text="$_label  $_body"
    _folded="$(printf '%s\n' "$_text" | fold -s -w 68)"
    _first=1
    while IFS= read -r _line; do
        _line="${_line%"${_line##*[![:space:]]}"}"
        [ -n "$_line" ] || continue
        if [ "$_first" -eq 1 ]; then
            "$_fn" "$_line"
            _first=0
        else
            ui_note "$_line"
        fi
    done <<EOF
$_folded
EOF
}

ok_names() { emit_names ok "$1" "${2:-}"; }
warn_names() { emit_names warn "$1" "${2:-}"; }

# Space-or-newline names -> sorted unique single line.
as_line() {
    tr -s '[:space:]' '\n' | grep -v '^$' | sort -u | paste -sd ' ' -
}

# First dotted version token from `tool --version`.
cli_ver() {
    command -v "$1" >/dev/null 2>&1 || return 0
    "$1" --version 2>/dev/null | awk '
        match($0, /[0-9]+(\.[0-9]+)+/) {
            print substr($0, RSTART, RLENGTH)
            exit
        }
    '
}

# Name / version table under one ok or warn label.
# Versions dump is `brew list --versions` (newlines); cannot go through awk -v.
pkg_table() {
    _fn="$1"
    _label="$2"
    _names="${3:-}"
    _dump="${4:-}"
    [ -n "$_names" ] || return

    "$_fn" "$_label"

    {
        printf '%s\n' "$_dump"
        printf '%s\n' '__NAMES__'
        printf '%s' "$_names" | tr -s '[:space:]' '\n' | grep -v '^$' | sort -u
    } | awk -v dim="$C_DIM" -v reset="$C_RESET" '
        $0 == "__NAMES__" { in_names = 1; next }
        !in_names { if (NF >= 2) ver[$1] = $2; next }
        {
            names[++c] = $0
            if (length($0) > w) w = length($0)
        }
        END {
            for (i = 1; i <= c; i++) {
                v = ver[names[i]]
                if (v != "")
                    printf "          %-*s  %s%s%s\n", w, names[i], dim, v, reset
                else
                    printf "          %s\n", names[i]
            }
        }
    '
}

# Exact match in a newline-separated list, then basename (tap/name).
have_pkg() {
    _n="$1"
    _hay="$2"
    case $'\n'"$_hay"$'\n' in
        *$'\n'"$_n"$'\n'*) return 0 ;;
    esac
    _s="${_n##*/}"
    if [ "$_s" != "$_n" ]; then
        case $'\n'"$_hay"$'\n' in
            *$'\n'"$_s"$'\n'*) return 0 ;;
        esac
    fi
    return 1
}

# Receipt without the app: Caskroom left a symlink after /Applications was cleared.
cask_app_gone() {
    _root="${HOMEBREW_PREFIX:-/opt/homebrew}/Caskroom/$1"
    [ -d "$_root" ] || return 1
    for _app in "$_root"/*/*.app; do
        if [ -L "$_app" ] && [ ! -e "$_app" ]; then
            return 0
        fi
    done
    return 1
}

# Quoted tokens from one or more Brewfiles (`brew "foo"`, `cask "tap/bar"`).
brewfile_kind() {
    _kind="$1"
    shift
    [ "$#" -gt 0 ] || return 0
    awk -v kind="$_kind" '
        $1 == kind {
            name = $2
            gsub(/"/, "", name)
            sub(/,.*/, "", name)
            n = split(name, a, "/")
            print a[n]
        }
    ' "$@"
}

printf '\n'
printf '  %sdotfiles doctor%s\n' "$C_BOLD" "$C_RESET"
printf '  %ssays what is off · fixes nothing%s\n' "$C_DIM" "$C_RESET"

# ---------------------------------------------------------------- Tooling ---

ui_section "Tooling"

if xcode-select -p >/dev/null 2>&1; then
    _clt_ver="$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null \
        | awk -F': ' '/^version:/{print $2}')"
    ok "$(join "Xcode CLT" "${_clt_ver:-$(xcode-select -p)}")"
else
    bad "Xcode CLT is missing" "xcode-select --install"
fi

if command -v brew >/dev/null 2>&1; then
    ok "$(join brew "$(cli_ver brew)")"
else
    bad "Homebrew is missing" "run install.sh"
fi

# ----------------------------------------------------------------- GitHub ---

ui_section "GitHub"

_ssh_out="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1)"
if printf '%s' "$_ssh_out" | grep -q 'successfully authenticated'; then
    ok "SSH  $(printf '%s' "$_ssh_out" | sed 's/^Hi //; s/!.*//')"
else
    bad "SSH to github.com is not working" "gh auth login -p ssh -w"
fi

if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        ok "$(join gh "$(cli_ver gh)" authenticated)"
    else
        warn "$(join gh "$(cli_ver gh)" "is not authenticated")" "gh auth login -p ssh -w"
    fi
fi

# --------------------------------------------------------------- Dotfiles ---

ui_section "Dotfiles"

_age_key="$HOME/.config/chezmoi/key.txt"
if [ -s "$_age_key" ]; then
    _perm="$(stat -f '%Lp' "$_age_key" 2>/dev/null)"
    if [ "$_perm" = "600" ]; then
        ok "age key  ~/.config/chezmoi/key.txt"
    else
        warn "age key is mode ${_perm:-unknown}" "chmod 600 $_age_key"
    fi
else
    bad "age key is missing" "private encrypted files won't apply — copy it from your password manager"
fi

if command -v chezmoi >/dev/null 2>&1; then
    _chez_ver="$(cli_ver chezmoi)"
    _status="$(chezmoi status --source "$DOTFILES_DIR" 2>/dev/null | grep -v 'R 90-private.sh' || true)"
    if [ -z "$_status" ]; then
        ok "$(join chezmoi "$_chez_ver" applied)"
    else
        warn "$(join chezmoi "$_chez_ver" "is out of sync")" \
             "chezmoi diff --source $DOTFILES_DIR  ·  chezmoi apply --source $DOTFILES_DIR"
        printf '%s\n' "$_status" | head -10 | while read -r _line; do
            [ -n "$_line" ] && ui_note "$_line"
        done
    fi
fi

_repo_ver="$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || true)"
if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
    warn "$(join "dotfiles repo" "$_repo_ver" "has uncommitted changes")" \
         "git -C $DOTFILES_DIR status"
else
    ok "$(join repo "$_repo_ver" clean)"
fi

_ahead="$(git -C "$DOTFILES_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
if [ "${_ahead:-0}" -gt 0 ]; then
    warn "$_ahead commit(s) not pushed" "git -C $DOTFILES_DIR push"
fi

# ----------------------------------------------------------------- Private ---

ui_section "Private"

_priv="$HOME/.dotfiles-private"
_pcfg="$HOME/.config/chezmoi-private/chezmoi.toml"
_pstate="$HOME/.config/chezmoi-private/chezmoistate.boltdb"

if [ ! -d "$_priv/.git" ]; then
    warn "private repo is not checked out" "$_priv"
else
    _priv_ver="$(git -C "$_priv" rev-parse --short HEAD 2>/dev/null || true)"
    if [ -n "$(git -C "$_priv" status --porcelain 2>/dev/null)" ]; then
        warn "$(join "private repo" "$_priv_ver" "has uncommitted changes")" \
             "git -C $_priv status"
    else
        ok "$(join "private repo" "$_priv_ver" clean)"
    fi
    _pahead="$(git -C "$_priv" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    if [ "${_pahead:-0}" -gt 0 ]; then
        warn "$_pahead private commit(s) not pushed" "git -C $_priv push"
    fi
    if [ -f "$_pcfg" ] && command -v chezmoi >/dev/null 2>&1; then
        _pstatus="$(chezmoi --config "$_pcfg" --persistent-state "$_pstate" --source "$_priv" status 2>/dev/null)"
        if [ -z "$_pstatus" ]; then
            ok "private chezmoi applied"
        else
            warn "private chezmoi is out of sync" \
                 "pchezmoi diff  ·  pchezmoi apply"
            printf '%s\n' "$_pstatus" | head -10 | while read -r _line; do
                [ -n "$_line" ] && ui_note "$_line"
            done
        fi
    else
        warn "private chezmoi is not initialized" \
             "chezmoi apply — the apply hook sets it up"
    fi
    if [ -f "$_priv/doctor.sh" ]; then
        # shellcheck source=/dev/null
        . "$_priv/doctor.sh"
    fi
fi

# ------------------------------------------------------------------ Shell ---

ui_section "Shell"

_login_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
case "$_login_shell" in
    */zsh) ok "$(join "login shell" "$_login_shell" "$(cli_ver zsh)")" ;;
    *)     bad "login shell is ${_login_shell:-unknown}" "chsh -s /bin/zsh" ;;
esac

if [ -f "$HOME/.zshrc" ]; then
    ok "~/.zshrc"
else
    bad "~/.zshrc is missing" "chezmoi apply --source $DOTFILES_DIR ~/.zshrc"
fi

_prompt=""
_spaceship="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/spaceship/spaceship.zsh"
if [ -f "$_spaceship" ]; then
    _prompt="Spaceship"
else
    warn "Spaceship is not installed" "brew install spaceship"
fi

for _plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/share/$_plugin/$_plugin.zsh" ]; then
        if [ -n "$_prompt" ]; then _prompt="$_prompt · $_plugin"; else _prompt="$_plugin"; fi
    else
        warn "$_plugin is missing" "brew install $_plugin"
    fi
done
[ -n "$_prompt" ] && ok "$_prompt"

# --------------------------------------------------------------- Packages ---

ui_section "Packages"

if command -v brew >/dev/null 2>&1; then
    _vers_f="$(brew list --formula --versions 2>/dev/null || true)"
    _vers_c="$(brew list --cask --versions 2>/dev/null || true)"
    _inst_f="$(printf '%s\n' "$_vers_f" | awk '{print $1}')"
    _inst_c="$(printf '%s\n' "$_vers_c" | awk '{print $1}')"

    _brewfiles=("$DOTFILES_DIR/config/Brewfile")
    [ -f "$HOME/.dotfiles-private/Brewfile" ] && _brewfiles+=("$HOME/.dotfiles-private/Brewfile")

    _ok_f="" _miss_f=""
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        if have_pkg "$_p" "$_inst_f"; then
            _ok_f="${_ok_f}${_p} "
        else
            _miss_f="${_miss_f}${_p} "
        fi
    done <<EOF
$(brewfile_kind brew "${_brewfiles[@]}")
EOF

    _ok_c="" _miss_c="" _ghost_c="" _disk_c="" _left_c=""
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        if have_pkg "$_p" "$_inst_c"; then
            if cask_app_gone "$_p"; then
                _ghost_c="${_ghost_c}${_p} "
            else
                _ok_c="${_ok_c}${_p} "
            fi
        else
            _miss_c="${_miss_c}${_p} "
        fi
    done <<EOF
$(brewfile_kind cask "${_brewfiles[@]}")
EOF

    if [ -n "$_miss_c" ] && [ -f "$DOTFILES_DIR/scripts/cask-present.py" ]; then
        _still=""
        while IFS="$(printf '\t')" read -r _p _state; do
            [ -n "$_p" ] || continue
            case "$_state" in
                present) _disk_c="${_disk_c}${_p} " ;;
                leftover) _left_c="${_left_c}${_p} " ;;
                *) _still="${_still}${_p} " ;;
            esac
        done <<EOF
$(python3 "$DOTFILES_DIR/scripts/cask-present.py" --classify "${_brewfiles[@]/#/--brewfile=}" $_miss_c 2>/dev/null || true)
EOF
        _miss_c="$_still"
    fi

    pkg_table ok brew "$_ok_f" "$_vers_f"
    pkg_table ok cask "$_ok_c" "$_vers_c"
    pkg_table ok "cask  on disk" "$_disk_c"

    _miss_any=0
    if [ -n "$_miss_f" ]; then
        pkg_table warn "brew  missing" "$_miss_f"
        _miss_any=1
    fi
    if [ -n "$_miss_c" ]; then
        pkg_table warn "cask  missing" "$_miss_c"
        _miss_any=1
    fi
    if [ "$_miss_any" -eq 1 ]; then
        for _bf in "${_brewfiles[@]}"; do
            ui_note "brew bundle install --file=$_bf"
        done
    fi
    if [ -n "$_left_c" ]; then
        pkg_table warn "cask  leftovers, app is gone" "$_left_c"
        ui_note "brew bundle skips these"
    fi
    if [ -n "$_ghost_c" ]; then
        pkg_table warn "cask  app is gone" "$_ghost_c" "$_vers_c"
        ui_note "brew reinstall --cask <name>  (bundle skips these)"
    fi
fi

# -------------------------------------------------------------- Languages ---

ui_section "Languages"

if command -v asdf >/dev/null 2>&1 && [ -f "$HOME/.tool-versions" ]; then
    while read -r _tool _version _rest; do
        case "$_tool" in ''|\#*) continue ;; esac
        if asdf list "$_tool" 2>/dev/null | tr -d ' *' | grep -qxF "$_version"; then
            ok "$_tool  $_version"
        else
            warn "$_tool $_version is not installed" \
                 "asdf plugin add $_tool && asdf install $_tool $_version"
        fi
    done < "$HOME/.tool-versions"
fi

# ---------------------------------------------------------------- Summary ---

printf '\n'
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    printf '  %s✓  All %s checks passed.%s\n\n' "$C_GREEN" "$PASS" "$C_RESET"
    exit 0
fi

printf '  %s%s ok%s  ·  %s%s to look at%s  ·  %s%s broken%s\n\n' \
    "$C_GREEN"  "$PASS" "$C_RESET" \
    "$C_YELLOW" "$WARN" "$C_RESET" \
    "$C_RED"    "$FAIL" "$C_RESET"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
