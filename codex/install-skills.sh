#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
SKILLS_DIR="${CODEX_HOME}/skills"

log() {
	printf '[dotfiles] %s\n' "$*"
}

install_personal_launcher() {
	local src="${SCRIPT_DIR}/codex-personal"
	local dest="${HOME}/.local/bin/codex-personal"

	if [[ ! -f "${src}" ]]; then
		log "Skip personal Codex launcher (source file not found)."
		return
	fi

	mkdir -p "$(dirname "${dest}")"
	install -m 755 "${src}" "${dest}"
	log "Installed personal Codex launcher at ${dest}."
}

remove_global_instructions_link() {
	local src="${SCRIPT_DIR}/AGENTS.md"
	local dest="${CODEX_HOME}/AGENTS.md"

	if [[ -L "${dest}" && "$(readlink "${dest}")" == "${src}" ]]; then
		log "Removing retired global Codex instructions link."
		rm "${dest}"
	fi
}

remove_skill() {
	local name="$1"
	local dest="${SKILLS_DIR}/${name}"

	if [[ -d "${dest}" ]]; then
		log "Removing Codex skill: ${name}"
		rm -rf "${dest}"
	fi
}

mkdir -p "${SKILLS_DIR}"

install_personal_launcher
remove_global_instructions_link

remove_skill karpathy-guidelines
remove_skill academic-research-suite
remove_skill academic-writing-plan
remove_skill academic-writing-write
remove_skill academic-writing-review

log "Codex setup complete under ${CODEX_HOME}."
