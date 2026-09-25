<div align="center">

![dotfiles](assets/hero-v2.svg)

```bash
curl -fsSL alexiscreuzot.com/dots | sh
```

chezmoi · zsh · Homebrew · age

</div>

## Install

1. Run the one-liner and enter your Mac password once.
2. Approve GitHub in the browser, then confirm your name and email.
3. Choose apps, macOS defaults, and a private repo. If private is on, paste your age key.

![install flow](assets/install-flow-v2.svg)

## `dots`

Syncs both repos. Run it after you change anything, on any Mac.

![dots](assets/dots-v2.svg)

| Phase | Does |
| --- | --- |
| capture | Pulls live edits back into the repos |
| commit | Shows the changes and asks before committing |
| pull | Rebases on the latest from GitHub |
| apply | Writes configs, then the private repo |
| push | Sends your commits up |

Templates such as `~/.gitconfig` can't be pulled back, so edit those in the repo. The public repo is only pushed if you own it.

## `dots doctor`

Reports what is off and changes nothing. It checks tooling, GitHub, both repos, agent links, the shell, Brewfile packages, and `~/.tool-versions`.

![dots doctor](assets/doctor-v2.svg)

`✓` is fine. `!` is worth a look, with the fix on the line below. `✗` is broken and makes the exit code 1.

## Your private repo

Anything you don't want public goes in a second chezmoi repo: secrets, work config, your own apps and Dock. Create `<your GitHub user>/Dotfiles-private` and apply picks it up. It clones the repo to `~/.dotfiles-private` and applies it as its own chezmoi source, right after the public one. `dots` and `dots doctor` cover it from then on.

If the repo doesn't exist, can't be reached, or you declined it at install, apply skips it and carries on. Run `chezmoi init --prompt` to change your answer.

| File | Does |
| --- | --- |
| `.chezmoi.toml.tmpl` | Turns on age encryption with the key from install |
| `encrypted_private_dot_secrets.age` | Decrypts to `~/.secrets` |
| `dot_zshrc.private` | Sourced by `~/.zshrc`, after the public aliases and functions |
| `Brewfile` | Your apps, installed on top of the public Brewfile |
| `run_onchange_before_10-brew-bundle.sh.tmpl` | Installs that Brewfile whenever it changes |
| `run_onchange_after_30-macos-defaults.sh` | Your Dock and app defaults |
| `symlink_*.tmpl` | Links editor settings and agent skills to files kept in the repo |
| `doctor.sh` | Extra checks, sourced by `dots doctor` with its `ok`, `warn`, and `bad` helpers |
| `.chezmoiignore` | Keeps `Brewfile`, `doctor.sh`, and other repo-only files out of `~` |

Two of these need exact contents. The config points at the repo and the age key that install saved:

```toml
sourceDir = "{{ .chezmoi.homeDir }}/.dotfiles-private"
encryption = "age"

[age]
    identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/key.txt"
    recipient = "age1…"
```

The Brewfile script reuses the public installer. The hash comment is what makes it re-run when the Brewfile changes:

```bash
#!/bin/bash
# Brewfile hash: {{ include "Brewfile" | sha256sum }}
exec bash "$HOME/.dotfiles/scripts/brew-bundle.sh" "{{ .chezmoi.sourceDir }}/Brewfile"
```

`pchezmoi` is chezmoi pointed at the private repo, so every chezmoi command works through it. Use `pchezmoi edit ~/.secrets` to change a secret, and `pchezmoi add --encrypt <file>` to add a new one.

## Layout

```text
install.sh    the one-liner
home/         what chezmoi applies to ~: zsh, git, ssh, gh, tmux, dots, run scripts
config/       read in place: Brewfile, path, aliases, functions
scripts/      bootstrap, doctor, brew-bundle, shared terminal UI
assets/       README images
```

## Shell

| Command | Does |
| --- | --- |
| `dots` | Sync both repos |
| `dots doctor` | Report what is off |
| `pchezmoi` | chezmoi for your private repo |
| `o [path]` | Open a path, or the current directory |
| `size [path]` | Size of a file or directory |
| `retag <tag>` / `delete_git_tag <tag>` | Move or remove a tag, locally and on the remote |
| `z <dir>` | Jump to a directory with zoxide |
| `ls` · `ll` · `la` · `lt` | Listings through eza |

`fzf` adds Ctrl-T for files, Ctrl-R for history, and Alt-C for directories.
