#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="${HOME}/.local"
bin_dir="${install_dir}/bin"

mkdir -p "$bin_dir"
export PATH="$bin_dir:${HOME}/.bun/bin:$PATH"

log() {
	printf '[ubuntu-dotfiles] %s\n' "$*"
}

ensure_node() {
	if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
		log "Node.js and npm already installed."
		return
	fi

	log "Installing Node.js LTS under ${install_dir}..."
	curl -sL install-node.vercel.app/lts | bash -s -- --prefix="$install_dir" -y
	hash -r
}

ensure_bun() {
	if command -v bun >/dev/null 2>&1; then
		log "Bun already installed."
		return
	fi

	log "Installing Bun..."
	curl -fsSL https://bun.sh/install | bash
	hash -r
}

ensure_codex() {
	if ! command -v npm >/dev/null 2>&1; then
		log "Skip installing Codex CLI (requires npm)."
		return
	fi

	log "Installing/updating Codex CLI..."
	npm config set prefix "$install_dir"
	npm install -g @openai/codex

	local skill_installer="${repo_dir}/../dotfiles/codex/install-skills.sh"
	if [[ -f "$skill_installer" ]]; then
		log "Installing Codex skills from ${skill_installer}..."
		bash "$skill_installer"
	fi
}

ensure_node
ensure_bun
ensure_codex

log "Node.js, Bun, and Codex setup complete."
