# TeX Live

Local TeX Live setup for paper writing, installed outside mamba/conda.

The default install is intentionally scoped for `pdflatex` papers targeting:

- IEEE ComSoc Transactions / IEEEtran
- NeurIPS, ICML, ICLR, AAAI author kits
- ACM `acmart`

It avoids broad TeX Live collections such as `collection-fontsextra`,
`collection-latexextra`, and `collection-publishers`. Conference-specific
style files for NeurIPS/ICML/ICLR/AAAI are normally distributed inside each
author kit, so this setup installs the TeX Live dependencies they need rather
than trying to install those yearly `.sty` files globally.

## Install

```bash
bash texlive/install-texlive.sh
```

Defaults:

- TeX Live year: `2026`
- Install path: `$HOME/texlive/2026`
- Install scheme: `scheme-basic`
- Repository: `https://kr.mirrors.cicku.me/ctan/systems/texlive/tlnet`
- TeX Live docs/source files: disabled

Override defaults with environment variables:

```bash
TEXLIVE_YEAR=2026 TEXLIVE_DIR="$HOME/texlive/2026" INSTALL_SCHEME=scheme-basic bash texlive/install-texlive.sh
```

## Scope

The exact package list lives in `install-texlive.sh`. It is kept to named
packages, not collections, in these categories:

- Venue classes/styles available from TeX Live: `ieeetran`, `acmart`,
  `aaai-named`
- Common author-kit dependencies: AMS math/fonts/classes, `graphics`,
  `psnfss`, Times/Helvetica/Courier font metrics, `natbib`, `cite`,
  `hyperref`, `xcolor`, `caption`, `subfig`, `stfloats`/`dblfloatfix`,
  `booktabs`, `microtype`, `mathtools`, `cleveref`, `enumitem`, `algorithm`,
  `algorithmic`, `listings`, `lineno`, `geometry`, `multirow`
- `acmart` runtime dependencies: `newtx`, `libertine`, `inconsolata`,
  `cmap`, `comment`, `draftwatermark`, `environ`, `framed`, `hyperxmp`,
  `ncctools`, `pbalance`, `preprint`, `setspace`, `totpages`, `zref`
- Local SSIR IEEE manuscript extras: `tcolorbox`, `pgf`, `pdfcol`,
  `tikzfill`, `listingsutf8`, `mdframed`, `needspace`, `soul`, `catchfile`,
  `dutchcal`, `l3packages`

This setup does not install XeLaTeX/LuaLaTeX, `biber`, or `biblatex` by
default. Add those only for projects that require them.

## Reinstall After a Broad Install

If `$HOME/texlive/2026` was already installed with a broad scheme or broad
collections, changing this script will not remove existing packages. Reinstall
from a clean tree to reclaim disk space:

```bash
rm -rf "$HOME/texlive/2026"
bash texlive/install-texlive.sh
```

## Shell Setup

The PATH setup lives in `oh-my-zsh/custom/01_env.zsh`:

```zsh
export TEXLIVE_HOME="$HOME/texlive/2026"
export PATH="$TEXLIVE_HOME/bin/x86_64-linux:$PATH"
```

Open a new shell, or from zsh run:

```zsh
source ~/.zshrc
```

Then check:

```bash
which pdflatex
which latexmk
pdflatex --version
```

The expected binaries should resolve under:

```text
$HOME/texlive/2026/bin/x86_64-linux
```

If an activated mamba environment shadows TeX Live, check `which pdflatex` and
remove TeX packages from that mamba environment.

## Compile a Paper

For a standard `pdflatex + bibtex` paper:

```bash
cd /path/to/paper
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex
```

Clean generated build files:

```bash
latexmk -C main.tex
```
