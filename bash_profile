
	CLOUD_DIR=~/Library/Mobile\ Documents/com~apple~CloudDocs/Documents

#   Load the shell dotfiles, and then some:
#   * CLOUD_DIR/Dotfiles/path can be used to extend `$PATH`.
#   * CLOUD_DIR/Dotfiles/extra can be used for other settings you don’t want to commit.
#   ------------------------------------------------------------

    for file in "$CLOUD_DIR"/Dotfiles/{path,prompt,aliases,functions,extra}; do
        [ -r "$file" ] && [ -f "$file" ] && source "$file";
    done;
    unset file;

#   Symlink all the things!
#   ------------------------------------------------------------

#   Liftoff
#
    ln -sfn "$CLOUD_DIR"/Dotfiles/liftoff/liftoffrc ~/.liftoffrc
    ln -sfn "$CLOUD_DIR"/Dotfiles/liftoff/ ~/.liftoff