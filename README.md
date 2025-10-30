# Dotfiles

Modern, modular dotfiles setup with performance optimizations for zsh.

## Quick Setup

```bash
# Backup existing .zshrc
mv ~/.zshrc ~/.zshrc.backup

# Create symlink to dotfiles
ln -s ~/Documents/Dotfiles/_init_ ~/.zshrc

# Create secrets file for API tokens
cp ~/Documents/Dotfiles/.secrets.example ~/.secrets
nano ~/.secrets  # Add your tokens here
```

## Structure

- `_init_` - Main entry point (symlink to `~/.zshrc`)
- `path` - PATH configs, oh-my-zsh, and dev tools
- `aliases` - Command shortcuts
- `functions` - Custom shell functions
- `~/.secrets` - Private file for API tokens (not in repo)

## Performance

**Lazy loading** reduces startup from 2-3s → 300-500ms:
- **NVM** - Loads only when using `node`, `npm`, `npx`, or `nvm`
- **rbenv** - Loads only when using `rbenv`
- **pyenv** - Loads only when using `pyenv`

### Measure your speed
```bash
time zsh -i -c exit  # Should be under 500ms
```

### Go even faster (optional)

**Starship theme** (faster than Spaceship):
```bash
brew install starship
# In path file, replace ZSH_THEME line with:
eval "$(starship init zsh)"
```

**zinit** (faster than oh-my-zsh):
```bash
bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
```

**Profile to find bottlenecks**:
```bash
# Add to top of _init_: zmodload zsh/zprof
# Add to bottom of path: zprof
```

## Benchmark

| Configuration | Startup Time |
|---------------|--------------|
| oh-my-zsh + eager loading | 2000-3000ms |
| **Current setup (lazy loading)** | **300-500ms** |
| + Starship theme | 200-400ms |
| + zinit | 100-200ms |

## Security

Never commit tokens to git. Store in `~/.secrets`:
```bash
export HOMEBREW_GITHUB_API_TOKEN="your_token_here"
export OPENAI_API_KEY="your_key_here"
```

## Useful Aliases

Already configured:
- `c` - clear
- `gs`, `ga`, `gc`, `gp` - git shortcuts
- `cleanup` - remove all .DS_Store files
- `show`/`hide` - toggle hidden files in Finder
- `ports` - list listening ports
- `myip` - get public IP
