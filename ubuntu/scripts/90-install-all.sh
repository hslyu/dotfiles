#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/00-install-packages.sh"
"$script_dir/10-keyboard-caps-hangul.sh"
"$script_dir/20-install-fonts.sh"
"$script_dir/21-setup-fontconfig.sh"
"$script_dir/25-install-nerdfont.sh"
"$script_dir/30-install-whitesur.sh"
"$script_dir/35-setup-dock.sh"
"$script_dir/50-setup-wezterm.sh"
"$script_dir/60-install-node-bun-codex.sh"

echo "Ubuntu desktop setup complete."
