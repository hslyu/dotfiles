#!/usr/bin/env bash

set -euo pipefail

# Install desktop tools and setup dependencies.
sudo apt update
sudo apt install -y \
	gnome-tweaks \
	gnome-shell-extension-manager \
	gnome-shell-extensions \
	chrome-gnome-shell \
	ibus-hangul \
	git \
	curl \
	wget \
	unzip \
	fontconfig \
	python3 \
	make \
	gettext

echo "Packages installed."
