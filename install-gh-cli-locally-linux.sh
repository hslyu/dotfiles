#!/usr/bin/env bash

set -euo pipefail

install_dir="${HOME}/.local"
bin_dir="${install_dir}/bin"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
	echo "This installer supports Linux x86-64 only." >&2
	exit 1
fi

for command_name in curl tar sha256sum install; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Missing required command: ${command_name}" >&2
		exit 1
	fi
done

latest_url="$(curl -fsSIL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)"
tag="${latest_url##*/}"
version="${tag#v}"
archive="gh_${version}_linux_amd64.tar.gz"
release_url="https://github.com/cli/cli/releases/download/${tag}"
work_dir="$(mktemp -d)"

trap 'rm -rf "${work_dir}"' EXIT

curl -fsSL "${release_url}/${archive}" -o "${work_dir}/${archive}"
curl -fsSL "${release_url}/gh_${version}_checksums.txt" -o "${work_dir}/checksums.txt"
(
	cd "${work_dir}"
	grep "  ${archive}$" checksums.txt | sha256sum --check -
)

tar -xzf "${work_dir}/${archive}" -C "${work_dir}"
mkdir -p "${bin_dir}"
install -m 0755 "${work_dir}/gh_${version}_linux_amd64/bin/gh" "${bin_dir}/gh"

"${bin_dir}/gh" --version
