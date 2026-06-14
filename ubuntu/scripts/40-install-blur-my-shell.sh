#!/usr/bin/env bash

set -euo pipefail

uuid="blur-my-shell@aunetx"
workdir="$(mktemp -d)"
zip_path="$workdir/blur-my-shell.zip"

cleanup() {
	rm -rf "$workdir"
}
trap cleanup EXIT

shell_version="$(gnome-shell --version | awk '{print $3}')"

# Download the matching extension package from extensions.gnome.org.
python3 - "$uuid" "$shell_version" "$zip_path" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

uuid, shell_version, output = sys.argv[1:]
query = urllib.parse.urlencode({"uuid": uuid, "shell_version": shell_version})
api = f"https://extensions.gnome.org/extension-query/?{query}"

with urllib.request.urlopen(api) as response:
    data = json.load(response)

extensions = data.get("extensions", [])
if not extensions:
    raise SystemExit(f"No extension package found for GNOME Shell {shell_version}")

download_url = extensions[0]["download_url"]
if download_url.startswith("/"):
    download_url = "https://extensions.gnome.org" + download_url

urllib.request.urlretrieve(download_url, output)
print(download_url)
PY

# Install and enable the extension.
gnome-extensions install --force "$zip_path"
gnome-extensions enable "$uuid" || true

echo "Blur My Shell installed. Log out and back in if GNOME reports an extension error."
