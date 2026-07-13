#!/usr/bin/env bash

set -euo pipefail

TEXLIVE_YEAR="${TEXLIVE_YEAR:-2026}"
TEXLIVE_DIR="${TEXLIVE_DIR:-${HOME}/texlive/${TEXLIVE_YEAR}}"
TEXLIVE_ARCH="${TEXLIVE_ARCH:-x86_64-linux}"
TEXLIVE_BIN="${TEXLIVE_DIR}/bin/${TEXLIVE_ARCH}"
TEXLIVE_MIRROR="${TEXLIVE_MIRROR:-https://kr.mirrors.cicku.me/ctan/systems/texlive/tlnet}"
INSTALL_SCHEME="${INSTALL_SCHEME:-scheme-basic}"
WORKDIR=""

PACKAGES=(
	latexmk

	# Venue classes and bibliography styles. AAAI/NeurIPS/ICML/ICLR class or
	# style files are distributed by their author kits, not as TeX Live classes.
	ieeetran
	acmart
	aaai-named

	# Common IEEE/NeurIPS/ICML/ICLR/AAAI/ACM author-kit dependencies.
	amscls
	amsfonts
	amsmath
	tools
	graphics
	psnfss
	times
	helvetic
	courier
	url
	natbib
	cite
	hyperref
	xcolor
	caption
	subfig
	sttools
	dblfloatfix
	booktabs
	microtype
	mathtools
	cleveref
	enumitem
	units
	fancyhdr
	eso-pic
	forloop
	todonotes
	algorithms
	algorithmicx
	listings
	newfloat
	float
	lineno
	geometry
	multirow

	# acmart runtime dependencies not pulled in reliably by package metadata.
	newtx
	libertine
	inconsolata
	cmap
	comment
	draftwatermark
	environ
	etoolbox
	framed
	hyperxmp
	iftex
	ncctools
	pbalance
	preprint
	refcount
	setspace
	totpages
	xkeyval
	xstring
	zref
	babel

	# Local IEEE paper extras used by the SSIR manuscript/tooling.
	colortbl
	tcolorbox
	pgf
	pdfcol
	tikzfill
	listingsutf8
	mdframed
	needspace
	soul
	catchfile
	dutchcal
	lipsum
	l3packages
	trimspaces

	# Small practical extras for pdflatex output and previews.
	cm-super
	type1cm
	dvipng
)

log() {
	printf '[texlive] %s\n' "$*"
}

cleanup() {
	if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
		rm -rf "$WORKDIR"
	fi
}

trap cleanup EXIT

fetch() {
	local url="$1"
	local dest="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$dest"
	elif command -v wget >/dev/null 2>&1; then
		wget -q "$url" -O "$dest"
	else
		printf 'install-texlive.sh requires curl or wget.\n' >&2
		return 1
	fi
}

install_texlive() {
	local archive installer_dir

	WORKDIR="$(mktemp -d)"
	archive="${WORKDIR}/install-tl-unx.tar.gz"

	log "Downloading TeX Live installer from ${TEXLIVE_MIRROR}..."
	fetch "${TEXLIVE_MIRROR}/install-tl-unx.tar.gz" "$archive"

	log "Extracting installer..."
	tar -xzf "$archive" -C "$WORKDIR"
	installer_dir="$(find "$WORKDIR" -maxdepth 1 -type d -name 'install-tl-*' | head -n 1)"

	log "Installing TeX Live ${TEXLIVE_YEAR} at ${TEXLIVE_DIR} with scheme=${INSTALL_SCHEME}..."
	perl "${installer_dir}/install-tl" \
		--no-interaction \
		--no-doc-install \
		--no-src-install \
		--scheme="${INSTALL_SCHEME}" \
		--texdir="${TEXLIVE_DIR}"
}

if [[ ! -x "${TEXLIVE_BIN}/tlmgr" ]]; then
	install_texlive
else
	log "TeX Live already installed at ${TEXLIVE_DIR}."
fi

export PATH="${TEXLIVE_BIN}:${PATH}"

log "Using tlmgr at $(command -v tlmgr)"
tlmgr option repository "$TEXLIVE_MIRROR"
tlmgr option docfiles 0
tlmgr option srcfiles 0

log "Installing paper-writing packages..."
tlmgr install "${PACKAGES[@]}"

log "TeX Live ready."
log "pdflatex: $(command -v pdflatex)"
log "latexmk:  $(command -v latexmk)"
