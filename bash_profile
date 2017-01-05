#   Load the shell dotfiles, and then some:
#   * ~/Dotfiles/path can be used to extend `$PATH`.
#   * ~/Dotfiles/extra can be used for other settings you don’t want to commit.
#   ------------------------------------------------------------
    for file in ~/Dotfiles/{path,prompt,aliases,functions,extra}; do
        [ -r "$file" ] && [ -f "$file" ] && source "$file";
    done;
    unset file;