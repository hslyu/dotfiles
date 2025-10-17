#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: $1 is not installed."
		echo "Install with: $2"
		exit 1
	fi
}

require_cmd uv "curl -LsSf https://astral.sh/uv/install.sh | sh"
require_cmd bun "curl -fsSL https://bun.sh/install | bash"

VENV="${HOME}/.virtualenvs/neovim"
if [[ -f "${VENV}" ]]; then
	echo "Error: ${VENV} exists and is not a directory."
	exit 1
fi

if [[ ! -d "${VENV}" ]]; then
	echo "Creating virtualenv at ${VENV}"
	uv venv "${VENV}" --python 3.12
fi

source "${VENV}/bin/activate"
uv pip install -U pynvim
deactivate

echo "Installing formatting tools for Conform.nvim"
uv tool install -U ruff
bun install -g @biomejs/biome
bun install -g @taplo/cli

echo "Installing CoC (fallback) prerequisites"
bun install -g neovim

if command -v dotnet >/dev/null 2>&1; then
	dotnet tool install csharpier -g || true
else
	echo "dotnet not found; skipping CSharpier installation."
fi

if ! command -v stylua >/dev/null 2>&1; then
	bun install -g @johnnymorganz/stylua-bin
fi

if ! command -v prettier >/dev/null 2>&1; then
	bun install -g prettier
fi

if ! command -v fd >/dev/null 2>&1; then
	bun install -g fd-find
fi

LOCALBIN="${HOME}/.local/bin"
if ! command -v rg >/dev/null 2>&1; then
	echo "Installing ripgrep to ${LOCALBIN}"
	TEMPDIR="$(mktemp -d)"
	mkdir -p "${LOCALBIN}"
	curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest |
		grep "browser_download_url.*-x86_64-unknown-linux-musl.tar.gz" |
		cut -d : -f 2,3 |
		tr -d \" |
		wget -qi - -O - | tar -xz --strip-components=1 -C "${TEMPDIR}"
	mv "${TEMPDIR}/rg" "${LOCALBIN}"
	rm -rf "${TEMPDIR}"
else
	echo "ripgrep already installed at $(command -v rg)"
fi

echo "Dependencies installed. python-import.nvim will be built automatically by lazy.nvim when the plugin is installed."
