#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$repo_dir/wezterm/wezterm.lua"
target_path="$HOME/.wezterm.lua"
install_dir="$HOME/.local/opt/wezterm"
bin_dir="$HOME/.local/bin"
appimage_path="$install_dir/wezterm.AppImage"
wezterm_bin="$bin_dir/wezterm"
desktop_dir="$HOME/.local/share/applications"
icon_dir="$HOME/.local/share/icons/hicolor/128x128/apps"
desktop_path="$desktop_dir/org.wezfurlong.wezterm.desktop"
icon_path="$icon_dir/org.wezfurlong.wezterm.png"

if [[ ! -f "$source_path" ]]; then
	echo "Missing $source_path" >&2
	exit 1
fi

install_wezterm() {
	if command -v wezterm >/dev/null 2>&1; then
		echo "WezTerm already installed at $(command -v wezterm)"
		return
	fi

	local source_appimage=""
	source_appimage="$(find "$HOME/Downloads" -maxdepth 1 -type f -name 'WezTerm*.AppImage' -print -quit 2>/dev/null || true)"

	if [[ -z "$source_appimage" ]]; then
		source_appimage="$appimage_path.download"
		echo "Downloading WezTerm AppImage..."
		python3 - "$source_appimage" <<'PY'
import json
import re
import sys
import urllib.request

output = sys.argv[1]
api = "https://api.github.com/repos/wez/wezterm/releases/latest"
pattern = re.compile(r"WezTerm-.*Ubuntu.*\.AppImage$")

with urllib.request.urlopen(api) as response:
    release = json.load(response)

for asset in release["assets"]:
    if pattern.search(asset["name"]):
        urllib.request.urlretrieve(asset["browser_download_url"], output)
        print(asset["name"])
        break
else:
    raise SystemExit("No WezTerm Ubuntu AppImage found in latest release")
PY
	fi

	mkdir -p "$install_dir" "$bin_dir"
	cp -f "$source_appimage" "$appimage_path"
	chmod +x "$appimage_path"
	ln -sfn "$appimage_path" "$wezterm_bin"
	echo "WezTerm installed at $wezterm_bin"
}

install_wezterm_desktop_entry() {
	local extract_dir=""
	extract_dir="$(mktemp -d)"

	(
		cd "$extract_dir"
		"$appimage_path" --appimage-extract >/dev/null
	)

	mkdir -p "$desktop_dir" "$icon_dir"
	cp -f "$extract_dir/squashfs-root/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png" "$icon_path"

	python3 - "$extract_dir/squashfs-root/usr/share/applications/org.wezfurlong.wezterm.desktop" "$desktop_path" "$wezterm_bin" <<'PY'
from pathlib import Path
import sys

source, target, wezterm_bin = map(Path, sys.argv[1:])
lines = []
for line in source.read_text().splitlines():
    if line.startswith("TryExec="):
        lines.append(f"TryExec={wezterm_bin}")
    elif line.startswith("Exec="):
        lines.append(f"Exec={wezterm_bin} start --cwd .")
    else:
        lines.append(line)

target.write_text("\n".join(lines) + "\n")
PY

	chmod 0644 "$desktop_path" "$icon_path"
	rm -rf "$extract_dir"

	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$desktop_dir" 2>/dev/null || true
	fi

	if command -v gtk-update-icon-cache >/dev/null 2>&1; then
		gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
	fi

	echo "WezTerm desktop entry installed at $desktop_path"
}

setup_wezterm_shortcut() {
	local binding_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/wezterm/"
	local bindings

	bindings="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
	bindings="$(
		python3 - "$bindings" "$binding_path" <<'PY'
import ast
import sys

raw, binding_path = sys.argv[1:]
bindings = [] if raw == "@as []" else ast.literal_eval(raw)
if binding_path not in bindings:
    bindings.append(binding_path)
print(str(bindings))
PY
	)"

	gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
	gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$bindings"
	gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding_path" name "WezTerm"
	gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding_path" command "$wezterm_bin"
	gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding_path" binding "<Primary><Alt>t"
}

install_wezterm
install_wezterm_desktop_entry

# Back up an existing non-matching file or symlink.
if [[ -e "$target_path" || -L "$target_path" ]]; then
	current_target="$(readlink "$target_path" 2>/dev/null || true)"
	if [[ "$current_target" != "$source_path" ]]; then
		backup_path="$target_path.backup.$(date +%Y%m%d-%H%M%S)"
		mv "$target_path" "$backup_path"
		echo "Backed up $target_path to $backup_path"
	fi
fi

ln -sfn "$source_path" "$target_path"

# Install WezTerm terminfo locally.
bash "$repo_dir/wezterm/terminfo.sh"

setup_wezterm_shortcut

echo "WezTerm installed, config linked, terminfo installed, and Ctrl+Alt+T bound."
