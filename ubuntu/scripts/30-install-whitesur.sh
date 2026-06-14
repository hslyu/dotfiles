#!/usr/bin/env bash

set -euo pipefail

workdir="$(mktemp -d)"

cleanup() {
	rm -rf "$workdir"
}
trap cleanup EXIT

mkdir -p "$HOME/.themes" "$HOME/.icons"

# Install WhiteSur GTK themes.
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$workdir/WhiteSur-gtk-theme"
(
	cd "$workdir/WhiteSur-gtk-theme"
	./install.sh -d "$HOME/.themes"
)

# Install WhiteSur icon themes.
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "$workdir/WhiteSur-icon-theme"
(
	cd "$workdir/WhiteSur-icon-theme"
	./install.sh -d "$HOME/.icons"
)

# Apply the user-level theme settings.
gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "WhiteSur theme and icons installed."
