#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OHMY_DIR="${SCRIPT_DIR}"
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"

mkdir -p "${BIN_DIR}"

log() {
	printf '[dotfiles] %s\n' "$*"
}

ensure_oh_my_zsh() {
	if [[ -d "${HOME}/.oh-my-zsh" ]]; then
		return
	fi

	log "Installing oh-my-zsh..."
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -- "" --unattended --keep-zshrc
}

ensure_starship() {
	if command -v starship >/dev/null 2>&1; then
		return
	fi

	log "Installing starship..."
	sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- -b "${BIN_DIR}" -y
}

ensure_zoxide() {
	if command -v zoxide >/dev/null 2>&1; then
		return
	fi

	log "Installing zoxide..."
	curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
}

ensure_fzf() {
	if command -v fzf >/dev/null 2>&1; then
		return
	fi

	log "Installing fzf..."
	git clone --depth 1 https://github.com/junegunn/fzf.git "${HOME}/.fzf"
	"${HOME}/.fzf/install" --bin
}

ensure_thefuck() {
	if command -v thefuck >/dev/null 2>&1; then
		return
	fi

	if command -v uv >/dev/null 2>&1; then
		log "Installing thefuck via uv..."
		uv tool install --python 3.11 thefuck
	elif command -v pipx >/dev/null 2>&1; then
		log "Installing thefuck via pipx..."
		pipx install thefuck
	else
		log "Skip installing thefuck (requires uv or pipx)."
	fi
}

ensure_bun() {
	if command -v bun >/dev/null 2>&1; then
		return
	fi

	log "Installing Bun..."
	curl -fsSL https://bun.sh/install | bash
}

setup_basedpyright_tools() {
	local bun_bin=""
	if command -v bun >/dev/null 2>&1; then
		bun_bin="$(command -v bun)"
	elif [[ -x "${HOME}/.bun/bin/bun" ]]; then
		bun_bin="${HOME}/.bun/bin/bun"
	elif [[ -x "${HOME}/.local/bin/bun" ]]; then
		bun_bin="${HOME}/.local/bin/bun"
	fi

	if [[ -z "${bun_bin}" ]]; then
		log "Skip basedpyright tools setup (bun not installed)."
		return
	fi

	local tool_dir="${OHMY_DIR}/scripts/basedpyright-tools"
	if [[ ! -d "${tool_dir}" ]]; then
		log "Skip basedpyright tools setup (directory not found)."
		return
	fi

	log "Installing basedpyright tool dependencies..."
	(
		cd "${tool_dir}"
		"${bun_bin}" install
	)
}

ensure_oh_my_zsh
ensure_starship
ensure_zoxide
ensure_fzf
ensure_bun
ensure_thefuck
setup_basedpyright_tools

log "All optional tools checked."
