# Dotfiles

## How to use
Just clone this repo into your Home `~` folder. 

Add this to your ~/.zshrc
```bash
for file in ~/Dotfiles/{path,aliases,functions}; do
    [ -r "$file" ] && [ -f "$file" ] && source "$file";
done;
unset file;

```
