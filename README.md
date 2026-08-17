# Dotfiles

macOS setup managed with [chezmoi](https://www.chezmoi.io/) — shell, app configs,
packages, system defaults, and age-encrypted secrets. A fresh Mac goes from box to
fully configured with two commands.

## Quickstart (new Mac)

```bash
git clone https://github.com/alexiscreuzot/Dotfiles.git ~/Developer/Dotfiles
~/Developer/Dotfiles/bootstrap.sh
```

- Running `git` on a fresh Mac triggers the Xcode CLT install prompt — accept it,
  wait for it to finish, then run the clone again.
- When prompted, restore your **age secret key** (from your password manager) to
  `~/.config/chezmoi/key.txt` — it's the only manual step.

Bootstrap then installs Homebrew, chezmoi, every Brewfile package/app, oh-my-zsh,
applies macOS defaults and all config files. Restart the terminal when done.

> If the repo is ever made public (safe — secrets are encrypted), this becomes a
> one-liner:
> `sh -c "$(curl -fsSL https://raw.githubusercontent.com/alexiscreuzot/Dotfiles/master/install.sh)"`

## How it works

This repo **is** the chezmoi source directory. `chezmoi apply` copies files to
their targets (`dot_zshrc` → `~/.zshrc`, `dot_config/...` → `~/.config/...`) and
runs automation scripts:

| File | Purpose |
|------|---------|
| `path`, `aliases`, `functions` | Shell fragments sourced by `.zshrc` |
| `Brewfile` | All brew formulae, casks, VS Code extensions |
| `run_onchange_before_10-brew-bundle.sh.tmpl` | Re-runs `brew bundle` when the Brewfile changes |
| `run_once_after_20-oh-my-zsh.sh` | Installs oh-my-zsh if missing |
| `run_onchange_after_30-macos-defaults.sh.tmpl` | macOS preferences (Finder, Dock, keyboard, screenshots) |
| `encrypted_private_dot_secrets.age` | age-encrypted secrets → `~/.secrets` |
| `bootstrap.sh` / `install.sh` | Fresh-Mac setup (local / curl entry point) |

## Daily workflow

```bash
chezmoi edit ~/.zshrc   # edit a managed file (through the repo)
chezmoi re-add          # or: pull edits made to live files back into the repo
chezmoi apply           # push repo state → home directory
chezmoi diff            # preview changes before applying
chezmoi add ~/.foo      # start managing a new file
```

Then commit and push — plain git workflow. Changes to `Brewfile` or the macOS
defaults script re-run automatically on the next `apply`.

## Secrets

- Private key lives at `~/.config/chezmoi/key.txt` — backed up in your password
  manager, never committed (`.gitignore` covers it).
- Edit secrets: `chezmoi edit ~/.secrets` (decrypts → edit → re-encrypts → applies).
- Encrypt a new file: `chezmoi add --encrypt ~/.foo`.

## Notes

- `cursor` and `sublime-text` casks warn on machines where the apps were installed
  manually. Adopt them with `brew install --cask --force <name>` (app closed).
- Git and SSH configs are intentionally unmanaged; `chezmoi add ~/.gitconfig` if
  that changes.
