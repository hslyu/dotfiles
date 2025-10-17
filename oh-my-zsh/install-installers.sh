#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
mkdir -p "${BIN_DIR}"

log() {
	printf '[light-shell] %s\n' "$*"
}

ensure_node() {
	if command -v node >/dev/null 2>&1; then
		return
	fi

	log "Installing Node.js (LTS) under ${INSTALL_DIR}..."
	curl -sL install-node.vercel.app/lts | bash -s -- --prefix="${INSTALL_DIR}" -y
}

ensure_bun() {
	if command -v bun >/dev/null 2>&1; then
		log "Bun already installed."
		return
	fi

	log "Installing Bun..."
	curl -fsSL https://bun.sh/install | bash
}

ensure_uv() {
	if command -v uv >/dev/null 2>&1; then
		log "uv already installed."
		return
	fi

	log "Installing uv..."
	curl -LsSf https://astral.sh/uv/install.sh | sh
}

ensure_miniforge() {
	if command -v conda >/dev/null 2>&1; then
		log "conda already installed."
		return
	fi

	local installer="${HOME}/bin/Miniforge3-$(uname)-$(uname -m).sh"
	local target="${HOME}/bin/miniforge3"

	log "Installing Miniforge3 at ${target}..."
	mkdir -p "${HOME}/bin"
	wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" -O "${installer}"
	bash "${installer}" -b -p "${target}"
	rm -f "${installer}"
}

ensure_rustup() {
	if command -v rustc >/dev/null 2>&1; then
		log "rustup toolchain already present, skipping bootstrap."
		rustup self update || true
	else
		log "Installing rustup with default stable toolchain..."
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
		source "${HOME}/.cargo/env"
		rustup default stable
	fi
}

ensure_cargo_binstall() {
	if command -v cargo-binstall >/dev/null 2>&1; then
		return
	fi

	log "Installing cargo-binstall..."
	curl -L --proto '=https' --tlsv1.2 -sSf \
		https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
}

ensure_node
ensure_bun
ensure_uv
ensure_miniforge
ensure_rustup
ensure_cargo_binstall

log "Bootstrap installers complete."
