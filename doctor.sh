#!/bin/bash
# Reports on a machine set up by install.sh / bootstrap.sh. Changes nothing.
set -u

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# shellcheck source=ui.sh
. "$DOTFILES_DIR/ui.sh"

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

# Quoted tokens from the Brewfile (`brew "foo"`, `cask "tap/bar"`).
brewfile_kind() {
    awk -v kind="$1" '
        $1 == kind {
            name = $2
            gsub(/"/, "", name)
            sub(/,.*/, "", name)
            n = split(name, a, "/")
            print a[n]
        }
    ' "$DOTFILES_DIR/Brewfile"
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
    bad "age key is missing" "encrypted files won't apply — copy it from Bitwarden"
fi

_secrets="$HOME/.secrets"
if [ -s "$_secrets" ]; then
    _jira_keys=0
    grep -q 'JIRA_EMAIL=' "$_secrets" && _jira_keys=$((_jira_keys + 1))
    grep -q 'JIRA_TOKEN=' "$_secrets" && _jira_keys=$((_jira_keys + 1))
    grep -q 'JIRA_DOMAIN=' "$_secrets" && _jira_keys=$((_jira_keys + 1))
    if [ "$_jira_keys" -eq 3 ]; then
        ok "Jira credentials  ~/.secrets"
    else
        bad "Jira credentials incomplete in ~/.secrets" \
            "chezmoi edit ~/.secrets — need JIRA_EMAIL, JIRA_TOKEN, JIRA_DOMAIN"
    fi
else
    bad "~/.secrets is missing" "need the age key, then chezmoi apply --source $DOTFILES_DIR"
fi

if [ -x "$HOME/.local/bin/jira" ]; then
    ok "jira  ~/.local/bin/jira"
else
    bad "jira CLI is missing" "chezmoi apply --source $DOTFILES_DIR ~/.local/bin/jira"
fi

if command -v chezmoi >/dev/null 2>&1; then
    _chez_ver="$(cli_ver chezmoi)"
    _status="$(chezmoi status --source "$DOTFILES_DIR" 2>/dev/null)"
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

# ------------------------------------------------------------------ Cursor ---

ui_section "Cursor"

_cursor_ok=""
if [ -d "/Applications/Cursor.app" ]; then
    _cursor_ok="$(join Cursor.app "$(defaults read /Applications/Cursor.app/Contents/Info \
        CFBundleShortVersionString 2>/dev/null || true)")"
else
    bad "Cursor.app is missing" "brew install --cask cursor"
fi

_cursor_settings="$HOME/Library/Application Support/Cursor/User/settings.json"
if [ -f "$_cursor_settings" ]; then
    if [ -n "$_cursor_ok" ]; then
        _cursor_ok="$_cursor_ok · settings"
    else
        _cursor_ok="settings"
    fi
else
    warn "Cursor settings are missing" "chezmoi apply --source $DOTFILES_DIR"
fi
[ -n "$_cursor_ok" ] && ok "$_cursor_ok"

_mcp="$HOME/.cursor/mcp.json"
if [ -s "$_mcp" ]; then
    if command -v jq >/dev/null 2>&1; then
        _servers="$(jq -r '.mcpServers // {} | keys[]' "$_mcp" 2>/dev/null | sort | paste -sd ' ' -)"
        if [ -n "$_servers" ]; then
            ok_names "mcp" "$_servers"
        else
            warn "mcp.json has no servers"
        fi
    else
        ok "mcp.json"
    fi
else
    bad "mcp.json is missing" "need the age key, then chezmoi apply --source $DOTFILES_DIR"
fi

_cursor_src="$DOTFILES_DIR/dot_cursor"

_ok_cmds=""
if [ -d "$_cursor_src/commands" ]; then
    for _src in "$_cursor_src/commands"/*.md; do
        [ -f "$_src" ] || continue
        _name="$(basename "$_src" .md)"
        if [ -f "$HOME/.cursor/commands/${_name}.md" ]; then
            _ok_cmds="${_ok_cmds}${_name} "
        else
            bad "/$_name  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/commands/${_name}.md"
        fi
    done
fi
[ -n "$_ok_cmds" ] && ok_names "commands" "$(printf '%s' "$_ok_cmds" | as_line)"

_ok_skills=""
if [ -d "$_cursor_src/skills" ]; then
    for _src in "$_cursor_src/skills"/*/SKILL.md; do
        [ -f "$_src" ] || continue
        _name="$(basename "$(dirname "$_src")")"
        if [ -f "$HOME/.cursor/skills/${_name}/SKILL.md" ]; then
            _ok_skills="${_ok_skills}${_name} "
        else
            bad "skill  $_name  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/skills/${_name}/SKILL.md"
        fi
    done
fi
[ -n "$_ok_skills" ] && ok_names "skills" "$(printf '%s' "$_ok_skills" | as_line)"

_ok_rules=""
if [ -d "$_cursor_src/rules" ]; then
    for _src in "$_cursor_src/rules"/*.mdc; do
        [ -f "$_src" ] || continue
        _name="$(basename "$_src" .mdc)"
        if [ -f "$HOME/.cursor/rules/${_name}.mdc" ]; then
            _ok_rules="${_ok_rules}${_name} "
        else
            bad "rule  $_name  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/rules/${_name}.mdc"
        fi
    done
fi
[ -n "$_ok_rules" ] && ok_names "rules" "$(printf '%s' "$_ok_rules" | as_line)"

_extra_cmds=""
if [ -d "$HOME/.cursor/commands" ]; then
    for _live in "$HOME/.cursor/commands"/*.md; do
        [ -f "$_live" ] || continue
        _name="$(basename "$_live")"
        if [ ! -f "$_cursor_src/commands/$_name" ]; then
            _extra_cmds="${_extra_cmds}${_name%.md} "
        fi
    done
fi
if [ -n "$_extra_cmds" ]; then
    warn_names "commands only on this machine" "$(printf '%s' "$_extra_cmds" | as_line)"
    ui_note "chezmoi add $HOME/.cursor/commands/<name>.md"
fi

_mh="$HOME/.cursor/monthly-hours"
_mh_ok=""
if [ -f "$_mh/report.py" ] && [ -f "$_mh/invoice.py" ]; then
    _mh_ok="scripts"
else
    bad "monthly-hours scripts are missing" \
        "chezmoi apply --source $DOTFILES_DIR $_mh"
fi
if [ -s "$_mh/config.json" ]; then
    if [ -n "$_mh_ok" ]; then _mh_ok="$_mh_ok · config"; else _mh_ok="config"; fi
else
    bad "monthly-hours config.json is missing" \
        "need the age key, then chezmoi apply --source $DOTFILES_DIR"
fi
if [ -x "$_mh/.venv/bin/python" ]; then
    _py_ver="$("$_mh/.venv/bin/python" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)"
    _venv_bit="$(join venv "$_py_ver")"
    if [ -n "$_mh_ok" ]; then _mh_ok="$_mh_ok · $_venv_bit"; else _mh_ok="$_venv_bit"; fi
else
    warn "monthly-hours venv is missing" \
         "chezmoi apply — the apply hook creates $_mh/.venv"
fi
[ -n "$_mh_ok" ] && ok "monthly-hours  $_mh_ok"

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

if [ -d "$HOME/.oh-my-zsh" ]; then
    _omz_owner="$(stat -f %Su "$HOME/.oh-my-zsh" 2>/dev/null || true)"
    if [ -n "$_omz_owner" ] && [ "$_omz_owner" != "$(id -un)" ]; then
        warn "oh-my-zsh is owned by $_omz_owner" \
            "bash $DOTFILES_DIR/bootstrap.sh"
    fi
fi

_prompt=""
if [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    _prompt="$(join oh-my-zsh "$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)")"
else
    warn "oh-my-zsh is not installed" "bash $DOTFILES_DIR/run_once_after_20-oh-my-zsh.sh"
fi

_theme="$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme"
if [ -f "$_theme" ]; then
    if [ -n "$_prompt" ]; then _prompt="$_prompt · Spaceship"; else _prompt="Spaceship"; fi
else
    warn "Spaceship theme is not linked" "bash $DOTFILES_DIR/run_once_after_20-oh-my-zsh.sh"
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

    _ok_f="" _miss_f=""
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        if have_pkg "$_p" "$_inst_f"; then
            _ok_f="${_ok_f}${_p} "
        else
            _miss_f="${_miss_f}${_p} "
        fi
    done <<EOF
$(brewfile_kind brew)
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
$(brewfile_kind cask)
EOF

    if [ -n "$_miss_c" ] && [ -f "$DOTFILES_DIR/cask-present.py" ]; then
        _still=""
        while IFS="$(printf '\t')" read -r _p _state; do
            [ -n "$_p" ] || continue
            case "$_state" in
                present) _disk_c="${_disk_c}${_p} " ;;
                leftover) _left_c="${_left_c}${_p} " ;;
                *) _still="${_still}${_p} " ;;
            esac
        done <<EOF
$(python3 "$DOTFILES_DIR/cask-present.py" --classify --brewfile "$DOTFILES_DIR/Brewfile" $_miss_c 2>/dev/null || true)
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
        ui_note "brew bundle install --file=$DOTFILES_DIR/Brewfile"
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
elif [ ! -f "$HOME/.tool-versions" ]; then
    warn "~/.tool-versions is not applied" \
         "chezmoi init --apply --source $DOTFILES_DIR"
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
