# Dotfiles

## How to use
Just clone this repo into your Home `~` folder. 
Create a symbolic link from `.bash_profile` to `YOUR_DOTFILES_DIRECTORY/bash_profile`.

```
rm ~/.bash_profile
ln -s YOUR_DOTFILES_DIRECTORY/bash_profile ~/.bash_profile
```

You can follow the same procedure for each dotfile you want to version. Create a folder dedicated to it in the `Dotfile` directory, then symlink to it in `~`.
Alternatively, you can put any new symlink creation directly into `bash_profile` so it gets done automatically when launching a new terminal.