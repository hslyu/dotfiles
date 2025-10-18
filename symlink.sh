#!/usr/bin/env bash
#!/usr/bin/env bash

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

backup_and_link() {
	local relpath="$1"
	local target_dir="$2"

	local base
	base="$(basename "$relpath")"
	local dest="${target_dir}/${base}"

	mkdir -p "$target_dir"
	if [[ -e "$dest" || -L "$dest" ]]; then
		echo "[dotfiles] Backing up ${dest} -> ${dest}~"
		rm -rf "${dest}~"
		mv "$dest" "${dest}~"
	fi

	ln -s "${CURRENT_DIR}/${relpath}" "${target_dir}"
}

echo "[dotfiles] Linking core configs"
backup_and_link nvim ~/.config
backup_and_link nvim/.vimrc ~
backup_and_link nvim-coc ~/.config
backup_and_link tmux/.tmux.conf ~
backup_and_link oh-my-zsh/.zshrc ~
backup_and_link oh-my-zsh/.dircolors ~
backup_and_link oh-my-zsh ~/.config
backup_and_link oh-my-zsh/starship.toml ~/.config

if [[ -d "${CURRENT_DIR}/wezterm" ]]; then
	backup_and_link wezterm ~/.config
fi

if [[ -d "${CURRENT_DIR}/helix" ]]; then
	backup_and_link helix ~/.config
fi

if [[ -f "${CURRENT_DIR}/cargo/config.toml" ]]; then
	mkdir -p ~/.cargo
	backup_and_link cargo/config.toml ~/.cargo
fi

if [[ -f "${CURRENT_DIR}/conda/.condarc" ]]; then
	backup_and_link conda/.condarc ~
fi

case "$OSTYPE" in
darwin*)
	for item in karabiner skhd yabai hammerspoon; do
		if [[ -d "${CURRENT_DIR}/${item}" ]]; then
			backup_and_link "${item}" ~/.config
		fi
	done
	;;
linux-gnu*)
	if [[ -d "${CURRENT_DIR}/autokey/data" ]]; then
		backup_and_link autokey/data ~/.config/autokey
	fi
	;;
esac

echo "[dotfiles] Symlinks created."
