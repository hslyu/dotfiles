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

echo "Installing CoC  prerequisites"
bun install -g neovim


if ! command -v stylua >/dev/null 2>&1; then
	bun install -g @johnnymorganz/stylua-bin
fi

if ! command -v prettier >/dev/null 2>&1; then
	bun install -g prettier
fi

if ! command -v tree-sitter >/dev/null 2>&1; then
	bun install -g tree-sitter-cli
fi

if ! command -v fd >/dev/null 2>&1; then
	bun install -g fd-find
fi

LOCALBIN="${HOME}/.local/bin"
if ! command -v rg &> /dev/null; then
  echo "ripgrep (rg) could not be found. Installing in $LOCALBIN"
  mkdir -p "$LOCALBIN"
  TEMPDIR=$(mktemp -d)
  curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest \
    | grep -E 'browser_download_url.*-x86_64-unknown-linux-musl\.tar\.gz"$' \
    | cut -d : -f 2,3 | tr -d '" ' \
    | xargs -n1 wget -qO "$TEMPDIR/ripgrep.tar.gz"
  tar -xzf "$TEMPDIR/ripgrep.tar.gz" --strip-components=1 -C "$TEMPDIR"
  mv "$TEMPDIR"/rg "$LOCALBIN"
  rm -f "$TEMPDIR/ripgrep.tar.gz"
  rm -rf "$TEMPDIR"
else
	echo "ripgrep found at $(which rg). Skipping installation."
fi

nvim --headless "+Lazy! sync" "+Lazy! load nvim-treesitter" "+TSUpdateSync" +qa
echo "Dependencies installed. python-import.nvim will be built automatically by lazy.nvim when the plugin is installed."
