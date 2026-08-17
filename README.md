# Dotfiles

macOS dotfiles managed with [chezmoi](https://www.chezmoi.io/), with age-encrypted
secrets, a Brewfile for all packages/apps, macOS system defaults, and a one-command
bootstrap for fresh machines.

## Fresh Mac setup

```bash
git clone git@github.com:alexiscreuzot/Dotfiles.git ~/Developer/Dotfiles
# (or https://github.com/alexiscreuzot/Dotfiles.git if SSH keys aren't set up yet)
~/Developer/Dotfiles/bootstrap.sh
```

The bootstrap installs Xcode CLT, Homebrew, chezmoi and age, then applies
everything: dotfiles, Brewfile packages, oh-my-zsh, and macOS defaults.

The one manual step: when prompted, restore the **age private key** to
`~/.config/chezmoi/key.txt` (keep a copy in your password manager). Without it,
encrypted secrets can't be decrypted.

## Daily usage

The repo at `~/Developer/Dotfiles` *is* the chezmoi source directory.

```bash
chezmoi apply          # push repo state → home directory
chezmoi re-add         # pull changes made to live files back into the repo
chezmoi diff           # preview what apply would change
chezmoi status         # files out of sync
chezmoi add ~/.foo     # start managing a new file
```

Then commit and push as usual — plain git workflow.

Changing `Brewfile` or the macOS defaults script re-runs them automatically
on the next `chezmoi apply` (hash-guarded `run_onchange` scripts).

## Secrets

Secrets (e.g. `NPM_TOKEN`) live in `encrypted_private_dot_secrets.age` and are
decrypted to `~/.secrets` (mode 600), sourced by the `path` fragment.

```bash
chezmoi edit ~/.secrets        # decrypts to a temp file, re-encrypts on save
```

Never commit plaintext secrets — `.gitignore` covers `.secrets` and `key.txt`.

## Layout

| Path | Purpose |
|------|---------|
| `path`, `aliases`, `functions` | Shell fragments sourced by `.zshrc` |
| `dot_zshrc`, `dot_tmux.conf`, `dot_tool-versions` | Managed home dotfiles |
| `dot_config/`, `Library/` | App configs (zed, gh, VS Code, Cursor, Sublime) |
| `encrypted_private_dot_secrets.age` | age-encrypted secrets → `~/.secrets` |
| `Brewfile` | All brew formulae, casks, VS Code extensions |
| `run_onchange_before_10-brew-bundle.sh.tmpl` | `brew bundle` when Brewfile changes |
| `run_once_after_20-oh-my-zsh.sh` | Installs oh-my-zsh if missing |
| `run_onchange_after_30-macos-defaults.sh.tmpl` | macOS system preferences |
| `bootstrap.sh` | Fresh-Mac installer |

## Notes

- `cursor` and `sublime-text` casks may warn on this machine because the apps
  were installed manually. To adopt them into brew: `brew install --cask --force cursor`
  (do this when Cursor isn't running). Sublime Text 3 config is preserved as-is.
- Git and SSH configs are intentionally not managed yet; add with
  `chezmoi add ~/.gitconfig` if wanted.
