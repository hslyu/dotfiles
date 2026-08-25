#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAL_CODEX_HOME="${CODEX_PERSONAL_HOME:-${HOME}/.codex-personal}"
DEFAULT_CODEX_HOME="${HOME}/.codex"

log() {
	printf '[dotfiles] %s\n' "$*"
}

if ! command -v codex >/dev/null 2>&1; then
	log "Codex CLI is not installed. Install it before registering accounts."
	exit 1
fi

log "Installing the personal launcher and Codex setup for both accounts."
CODEX_HOME="${PERSONAL_CODEX_HOME}" bash "${SCRIPT_DIR}/install-skills.sh"
CODEX_HOME="${DEFAULT_CODEX_HOME}" bash "${SCRIPT_DIR}/install-skills.sh"

log "Before login, the configured account separation is:"
log "  personal: CODEX_HOME=${PERSONAL_CODEX_HOME} (use 'codex-personal')"
log "  default:  CODEX_HOME=${DEFAULT_CODEX_HOME} (use 'codex')"
log "  both:     ${SCRIPT_DIR}/config.toml is shared; account sessions remain separate"

log "[1/2] Register the personal account using the device code shown next."
CODEX_HOME="${PERSONAL_CODEX_HOME}" codex login --device-auth
CODEX_HOME="${PERSONAL_CODEX_HOME}" codex login status

read -r -p "[2/2] Press Enter to register the default codex account with a different device-code login... "
CODEX_HOME="${DEFAULT_CODEX_HOME}" codex login --device-auth
CODEX_HOME="${DEFAULT_CODEX_HOME}" codex login status

log "Done. Use 'codex-personal' for the personal account and 'codex' for the default account."
