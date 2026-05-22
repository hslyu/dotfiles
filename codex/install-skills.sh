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
	local src="$2"
	local dest="${SKILLS_DIR}/${name}"

	if [[ ! -d "${src}" ]]; then
		log "Skip ${name} (source directory not found)."
		return
	fi

	log "Installing Codex skill: ${name}"
	mkdir -p "${dest}"
	rsync -a --delete "${src}/" "${dest}/"
}

ensure_submodules() {
	if [[ ! -d "${SCRIPT_DIR}/../.git" ]]; then
		return
	fi

	git -C "${SCRIPT_DIR}/.." submodule update --init --recursive \
		codex/skill-sources/andrej-karpathy-skills \
		codex/skill-sources/academic-research-skills-codex
}

mkdir -p "${SKILLS_DIR}"

ensure_submodules

install_skill karpathy-guidelines \
	"${SCRIPT_DIR}/skill-sources/andrej-karpathy-skills/skills/karpathy-guidelines"
install_skill academic-research-suite \
	"${SCRIPT_DIR}/skill-sources/academic-research-skills-codex/skills/academic-research-suite"

log "Codex skills installed under ${SKILLS_DIR}."
