#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
SKILLS_DIR="${CODEX_HOME}/skills"

log() {
	printf '[dotfiles] %s\n' "$*"
}

install_global_instructions() {
	local src="${SCRIPT_DIR}/AGENTS.md"
	local dest="${CODEX_HOME}/AGENTS.md"
	local backup="${dest}~"

	if [[ ! -f "${src}" ]]; then
		log "Skip global Codex instructions (source file not found)."
		return
	fi

	if [[ -L "${dest}" && "$(readlink "${dest}")" == "${src}" ]]; then
		log "Global Codex instructions already linked."
		return
	fi

	if [[ -e "${dest}" || -L "${dest}" ]]; then
		if [[ -e "${backup}" || -L "${backup}" ]]; then
			log "Cannot back up ${dest}: ${backup} already exists."
			return 1
		fi

		log "Backing up ${dest} -> ${backup}"
		mv "${dest}" "${backup}"
	fi

	log "Installing global Codex instructions."
	ln -s "${src}" "${dest}"
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

remove_stale_skill() {
	local name="$1"
	local dest="${SKILLS_DIR}/${name}"

	if [[ -d "${dest}" ]]; then
		log "Removing stale Codex skill: ${name}"
		rm -rf "${dest}"
	fi
}

ensure_submodules() {
	if [[ ! -d "${SCRIPT_DIR}/../.git" ]]; then
		return
	fi

	git -C "${SCRIPT_DIR}/.." submodule update --init --recursive \
		codex/skill-sources/andrej-karpathy-skills \
		codex/skill-sources/academic-research-skills-codex \
		codex/skill-sources/academic-writing-principles
}

mkdir -p "${SKILLS_DIR}"

ensure_submodules
install_global_instructions

remove_stale_skill academic-writing-principles

install_skill karpathy-guidelines \
	"${SCRIPT_DIR}/skill-sources/andrej-karpathy-skills/skills/karpathy-guidelines"
install_skill academic-research-suite \
	"${SCRIPT_DIR}/skill-sources/academic-research-skills-codex/skills/academic-research-suite"
install_skill academic-writing-plan \
	"${SCRIPT_DIR}/skill-sources/academic-writing-principles/skills/academic-writing-plan"
install_skill academic-writing-write \
	"${SCRIPT_DIR}/skill-sources/academic-writing-principles/skills/academic-writing-write"
install_skill academic-writing-review \
	"${SCRIPT_DIR}/skill-sources/academic-writing-principles/skills/academic-writing-review"

log "Codex instructions and skills installed under ${CODEX_HOME}."
