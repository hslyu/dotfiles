#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
SKILLS_DIR="${CODEX_HOME}/skills"

log() {
	printf '[dotfiles] %s\n' "$*"
}

install_skill() {
	local name="$1"
	local src="${SCRIPT_DIR}/skills/${name}"
	local dest="${SKILLS_DIR}/${name}"

	if [[ ! -d "${src}" ]]; then
		log "Skip ${name} (source directory not found)."
		return
	fi

	log "Installing Codex skill: ${name}"
	mkdir -p "${dest}"
	rsync -a --delete "${src}/" "${dest}/"
}

mkdir -p "${SKILLS_DIR}"

install_skill karpathy-guidelines
install_skill academic-research-suite

log "Codex skills installed under ${SKILLS_DIR}."
