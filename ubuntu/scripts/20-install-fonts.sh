#!/usr/bin/env bash

set -euo pipefail

workdir="$(mktemp -d)"
font_dir="$HOME/.local/share/fonts"
mkdir -p "$font_dir"

cleanup() {
	rm -rf "$workdir"
}
trap cleanup EXIT

download_latest_asset() {
	local repo="$1"
	local pattern="$2"
	local output="$3"

	python3 - "$repo" "$pattern" "$output" <<'PY'
import json
import re
import sys
import urllib.request

repo, pattern, output = sys.argv[1:]
api = f"https://api.github.com/repos/{repo}/releases/latest"
with urllib.request.urlopen(api) as response:
    release = json.load(response)

regex = re.compile(pattern)
for asset in release["assets"]:
    if regex.search(asset["name"]):
        urllib.request.urlretrieve(asset["browser_download_url"], output)
        print(asset["name"])
        break
else:
    raise SystemExit(f"No asset matched {pattern}")
PY
}

# Install Pretendard.
pretendard_zip="$workdir/pretendard.zip"
download_latest_asset "orioncactus/pretendard" "Pretendard-.*\\.zip$" "$pretendard_zip"
unzip -q "$pretendard_zip" -d "$workdir/pretendard"
find "$workdir/pretendard" -type f \( -name '*.otf' -o -name '*.ttf' \) -exec cp -f {} "$font_dir/" \;

# Install JetBrains Mono.
jetbrains_zip="$workdir/jetbrains-mono.zip"
download_latest_asset "JetBrains/JetBrainsMono" "JetBrainsMono-.*\\.zip$" "$jetbrains_zip"
unzip -q "$jetbrains_zip" -d "$workdir/jetbrains-mono"
find "$workdir/jetbrains-mono" -type f \( -name '*.otf' -o -name '*.ttf' \) -exec cp -f {} "$font_dir/" \;

# Install Nanum fonts from Ubuntu packages.
sudo apt update
sudo apt install -y fonts-nanum fonts-nanum-extra fonts-naver-d2coding

# Rebuild the full font cache. Nanum is installed under /usr/share/fonts by apt.
fc-cache -f

echo "Fonts installed."
