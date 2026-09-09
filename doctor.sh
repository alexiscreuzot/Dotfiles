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

printf '\n'
printf '  %sdotfiles doctor%s\n' "$C_BOLD" "$C_RESET"
printf '  %ssays what is off · fixes nothing%s\n' "$C_DIM" "$C_RESET"

# ---------------------------------------------------------------- Tooling ---

ui_section "Tooling"

if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode command line tools  $(xcode-select -p)"
else
    bad "Xcode command line tools are missing" "xcode-select --install"
fi

if command -v brew >/dev/null 2>&1; then
    ok "brew  $(brew --prefix)"
else
    bad "Homebrew is missing" "run install.sh"
fi

# command:formula, because a few commands are named differently than the formula
for _entry in git:git gh:gh chezmoi:chezmoi age:age jq:jq fd:fd rg:ripgrep \
              fzf:fzf zoxide:zoxide eza:eza bat:bat asdf:asdf; do
    _cmd="${_entry%%:*}"
    _formula="${_entry##*:}"
    if command -v "$_cmd" >/dev/null 2>&1; then
        ok "$_cmd"
    else
        warn "$_cmd is missing" "brew install $_formula"
    fi
done

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
        ok "gh  authenticated"
    else
        warn "gh is not authenticated" "gh auth login -p ssh -w"
    fi
fi

# --------------------------------------------------------------- Dotfiles ---

ui_section "Dotfiles"

_age_key="$HOME/.config/chezmoi/key.txt"
if [ -s "$_age_key" ]; then
    _perm="$(stat -f '%Lp' "$_age_key" 2>/dev/null)"
    if [ "$_perm" = "600" ]; then
        ok "age key  $_age_key"
    else
        warn "age key is mode ${_perm:-unknown}" "chmod 600 $_age_key"
    fi
else
    bad "age key is missing" "encrypted files won't apply — copy it from Bitwarden"
fi

if command -v chezmoi >/dev/null 2>&1; then
    _status="$(chezmoi status --source "$DOTFILES_DIR" 2>/dev/null)"
    if [ -z "$_status" ]; then
        ok "chezmoi  everything applied"
    else
        warn "chezmoi is out of sync" "chezmoi diff --source $DOTFILES_DIR  ·  chezmoi apply --source $DOTFILES_DIR"
        printf '%s\n' "$_status" | head -10 | while read -r _line; do
            [ -n "$_line" ] && ui_note "$_line"
        done
    fi
fi

if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
    warn "the dotfiles repo has uncommitted changes" "git -C $DOTFILES_DIR status"
else
    ok "dotfiles repo  clean"
fi

_ahead="$(git -C "$DOTFILES_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
if [ "${_ahead:-0}" -gt 0 ]; then
    warn "$_ahead commit(s) not pushed" "git -C $DOTFILES_DIR push"
fi

# ------------------------------------------------------------------ Cursor ---

ui_section "Cursor"

if [ -d "/Applications/Cursor.app" ]; then
    ok "Cursor.app"
else
    bad "Cursor.app is missing" "brew install --cask cursor"
fi

_cursor_settings="$HOME/Library/Application Support/Cursor/User/settings.json"
if [ -f "$_cursor_settings" ]; then
    ok "settings"
else
    warn "Cursor settings are missing" "chezmoi apply --source $DOTFILES_DIR"
fi

_mcp="$HOME/.cursor/mcp.json"
if [ -s "$_mcp" ]; then
    if command -v jq >/dev/null 2>&1; then
        _servers="$(jq -r '.mcpServers // {} | keys[]' "$_mcp" 2>/dev/null)"
        if [ -n "$_servers" ]; then
            while IFS= read -r _srv; do
                [ -n "$_srv" ] || continue
                ok "mcp  $_srv"
            done <<EOF
$_servers
EOF
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

if [ -d "$_cursor_src/commands" ]; then
    for _src in "$_cursor_src/commands"/*.md; do
        [ -f "$_src" ] || continue
        _name="$(basename "$_src" .md)"
        if [ -f "$HOME/.cursor/commands/${_name}.md" ]; then
            ok "/$_name"
        else
            bad "/$_name  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/commands/${_name}.md"
        fi
    done
fi

if [ -d "$_cursor_src/skills" ]; then
    for _src in "$_cursor_src/skills"/*/SKILL.md; do
        [ -f "$_src" ] || continue
        _name="$(basename "$(dirname "$_src")")"
        if [ -f "$HOME/.cursor/skills/${_name}/SKILL.md" ]; then
            ok "skill  $_name"
        else
            bad "skill  $_name  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/skills/${_name}/SKILL.md"
        fi
    done
fi

if [ -d "$_cursor_src/rules" ]; then
    for _src in "$_cursor_src/rules"/*.mdc; do
        [ -f "$_src" ] || continue
        _name="$(basename "$_src")"
        if [ -f "$HOME/.cursor/rules/$_name" ]; then
            ok "rule  ${_name%.mdc}"
        else
            bad "rule  ${_name%.mdc}  not applied" \
                "chezmoi apply --source $DOTFILES_DIR $HOME/.cursor/rules/$_name"
        fi
    done
fi

if [ -d "$HOME/.cursor/commands" ]; then
    for _live in "$HOME/.cursor/commands"/*.md; do
        [ -f "$_live" ] || continue
        _name="$(basename "$_live")"
        if [ ! -f "$_cursor_src/commands/$_name" ]; then
            warn "/${_name%.md}  only on this machine" "chezmoi add $HOME/.cursor/commands/$_name"
        fi
    done
fi

_mh="$HOME/.cursor/monthly-hours"
if [ -f "$_mh/report.py" ] && [ -f "$_mh/invoice.py" ]; then
    ok "monthly-hours scripts"
else
    bad "monthly-hours scripts are missing" \
        "chezmoi apply --source $DOTFILES_DIR $_mh"
fi
if [ -s "$_mh/config.json" ]; then
    ok "monthly-hours config"
else
    bad "monthly-hours config.json is missing" \
        "need the age key, then chezmoi apply --source $DOTFILES_DIR"
fi
if [ -x "$_mh/.venv/bin/python" ]; then
    ok "monthly-hours venv"
else
    warn "monthly-hours venv is missing" \
         "chezmoi apply — the apply hook creates $_mh/.venv"
fi

# ------------------------------------------------------------------ Shell ---

ui_section "Shell"

_login_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
case "$_login_shell" in
    */zsh) ok "login shell  $_login_shell" ;;
    *)     bad "login shell is ${_login_shell:-unknown}" "chsh -s /bin/zsh" ;;
esac

if [ -f "$HOME/.zshrc" ]; then
    ok "~/.zshrc  present"
else
    bad "~/.zshrc is missing" "chezmoi apply --source $DOTFILES_DIR ~/.zshrc"
fi

if [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    ok "oh-my-zsh  installed"
else
    warn "oh-my-zsh is not installed" "bash $DOTFILES_DIR/run_once_after_20-oh-my-zsh.sh"
fi

_theme="$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme"
if [ -f "$_theme" ]; then
    ok "Spaceship theme  linked"
else
    warn "Spaceship theme is not linked" "bash $DOTFILES_DIR/run_once_after_20-oh-my-zsh.sh"
fi

for _plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/share/$_plugin/$_plugin.zsh" ]; then
        ok "$_plugin  loaded"
    else
        warn "$_plugin is missing" "brew install $_plugin"
    fi
done

# --------------------------------------------------------------- Packages ---

ui_section "Packages"

if command -v brew >/dev/null 2>&1; then
    _bundle="$(brew bundle check --verbose --file="$DOTFILES_DIR/Brewfile" 2>&1)"
    _bundle_rc=$?
    if [ "$_bundle_rc" -eq 0 ]; then
        ok "Brewfile  everything installed"
    else
        warn "the Brewfile has missing entries" \
             "brew bundle install --file=$DOTFILES_DIR/Brewfile"
        printf '%s\n' "$_bundle" \
            | grep -iE 'needs to be installed|not installed' | head -15 \
            | while read -r _line; do
                [ -n "$_line" ] && ui_note "$_line"
            done
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
