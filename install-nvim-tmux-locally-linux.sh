#!/usr/bin/env bash

# neovim latest stable/nightly version
# nvim_tag=stable
# nvim_tag=nightly
nvim_tag=v0.11.3
mkdir ~/.local/bin -p
cd ~/.local/bin || exit
curl -LO https://github.com/neovim/neovim/releases/download/$nvim_tag/nvim-linux-x86_64.appimage
chmod u+x ./nvim-linux-x86_64.appimage
./nvim-linux-x86_64.appimage --appimage-extract
rsync -a squashfs-root/usr/ ~/.local/
rm nvim-linux-x86_64.appimage
rm -rf squashfs-root

# tmux latest version
mkdir ~/.local/bin -p
cd ~/.local/bin || exit
curl -s https://api.github.com/repos/kiyoon/tmux-appimage/releases/latest |
	grep "browser_download_url.*appimage" |
	cut -d : -f 2,3 |
	tr -d \" |
	wget -qi - &&
	chmod +x tmux.appimage
	./tmux.appimage --appimage-extract
	rsync -a squashfs-root/usr/ ~/.local/
	rm tmux.appimage
	rm -rf squashfs-root
