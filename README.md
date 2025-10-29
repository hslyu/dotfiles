# dotfiles that work without sudo

> [!NOTE]
>These dotfiles originate from a fork of [`kiyoon/dotfiles`](https://github.com/kiyoon/dotfiles) with local customizations. Refer to the upstream repository for additional context and history.

This is a modern Neovim, Tmux, Zsh configuration that supports installing everything locally (i.e. non-system-wide user install, not using sudo).  
You can enjoy working on a remote SSH server without root permission, just like you do locally.

![image](https://user-images.githubusercontent.com/12980409/218476082-8c400daf-7d9d-4d15-bf7a-f6b41d9191d9.png)

![image](https://user-images.githubusercontent.com/12980409/218475937-c9a51b2d-b4d6-499f-8787-012770410209.png)

![image](https://user-images.githubusercontent.com/12980409/218476252-9de93e0c-ddfe-486b-979a-5ded6a9425a9.png)

## Keep it stable!

This repository includes a GitHub Actions that automatically checks if the commit hasn't been made for 1 week.  
If it has not been updated for 1 week, we consider that commit to be 'stable' and automatically bump version with `stable` tag.  
In order to try the stable version, just run `dotstable` after setting up the zsh. This will also pull neovim plugin versions that have been used for the stable commit.

Also, it has many versions of vim configurations.

- `vi` to run a fully-featured bleeding-edge configuration of neovim.
- `vic` to run neovim with stable and mild configuration using CoC. It's a balance between the two, and should be used when the first option is broken.
- `lazyvim` to run pre-configured [LazyVim](https://github.com/LazyVim/LazyVim).
- `vim` to run original vim with no plugins (only simple `.vimrc`)
- `csvi` to read CSV files. `:CsvAlign` or `:TsvAlign` to align columns and `H`, `L` to move by columns.

## Features

### Zsh

- Feature-rich prompt powered by [Starship](https://starship.rs)
- Autocomplete, autosuggest
- Syntax highlighting
- Vim mode
- Fuzzy searching with [fzf](https://github.com/junegunn/fzf)
  - Try `Ctrl+t` to find file, `Alt+c` to change directory, `Ctrl+r` to reverse search commands.
- Smart change directory with [Zoxide](https://github.com/ajeetdsouza/zoxide)
  - Try `z <partial dirname..>` like `z dot` will go to the `~/.config/dotfiles`.
- Move between prompts: (OSC 133)
  - In Tmux: Ctrl + Alt + k/j
  - Outside Tmux (WezTerm setting): Shift + Up/Down

### Neovim

- Yank registers synchronised with tmux. Yank from neovim and paste on tmux. Copy from tmux and paste on neovim.
- See more in [nvim/README.md](nvim/README.md)

### Tmux

- Mouse-enabled interactive tree view with [Treemux](https://github.com/kiyoon/treemux)
- Status bar that shows battery, CPU, GPU, RAM, weather, and git with [tmux-dracula fork](https://github.com/kiyoon/tmux-dracula)
- See more in [tmux/README.md](tmux/README.md)

## Requirements

- Linux x86-64, macOS, Windows WSL2
- Neovim v0.11.3 (make sure you use this exact version)
- Tmux v3.5a
- Zsh v5.9 (in v5.8 highlighting will look weird and fzf-tab will remove some lines)


## Steps

1. Install dotfiles

```bash
cd ~/.config	# it doesn't have to be here. Just install anywhere
git clone https://github.com/kiyoon/dotfiles

# WARNING: ./symlink.sh will override existing dotfiles without validation (but will create a backup).
# The old dotfiles will be moved with '~' suffix.
# Use with care if you configured something manually.
cd dotfiles
./symlink.sh
```

2. Install zsh, oh-my-zsh

```bash
oh-my-zsh/zsh-local-install.sh
oh-my-zsh/install-installers.sh
source ~/.bashrc  # make cargo and bun available
oh-my-zsh/apps-local-install.sh
oh-my-zsh/launch-zsh-in-bash.sh
git submodule update --init --remote  # Install and update all zsh plugins
```

NOTE: some steps like `apps-local-install.sh` may not work from the first run, because they break with missing dependencies easily.  
Kindly try it again after re-opening your terminal, if some error occurs.

Open your terminal again and you'll see you're running zsh.

See [oh-my-zsh/README.md](oh-my-zsh/README.md) for details.

3. Install neovim and tmux

You need Neovim v0.11.3.

On Linux, you can install locally using:

```bash
./install-nvim-tmux-locally-linux.sh
```

This will download the latest appimage for each and extract at `~/.local/bin`.

Install neovim dependencies:

```bash
bash nvim/install-dependencies.sh
```

Install tmux plugins:

```bash
bash tmux/install-plugins.sh
```

4. Install others

```bash
# You might want to symlink dotfiles again in case some scripts overrode them
./symlink.sh
# You only need to install it to the local computer, not in SSH host computer.
./install-nerdfont.sh
# If you're using wezterm (recommended), install terminfo
wezterm/terminfo.sh
```

5. Install / Update dotfiles, apps, plugins etc.

```zsh
# WARNING: This includes calling ./symlink.sh so the dotfile symlinks will be updated.
dotupdate			# Use if you want to update to the latest commit
dotstable			# Use if you want to use the stable tag
dotupdate <tag>		# Specify the tag/commit you want to use
```

## SSH with WezTerm
If you ssh into a remote server, it won't understand the terminal and the UI will break (like backspace seems to work like space).  
You need to install `wezterm.terminfo` on the server.

```bash
bash wezterm/terminfo.sh <ssh_server_name>  # run this before ssh into a new server. Only need it once.
ssh <ssh_server_name>
```

In NeoVim, `<F13>` means `Shift + F1`, `<F25>` means `Ctrl + F1`.

Sometimes it is hard to pass the exact key sequence to the terminal. For example, skhd intercepts `F6` and it can't
pass the same key to the terminal. Thus, I used `F5` in some cases.
