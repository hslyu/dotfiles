#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="$HOME/.virtualenvs/tmux"
SYS_PY="/usr/bin/python3"
VENV_PY="$VENV_DIR/bin/python3"

# 이 스크립트를 tmux/ 폴더에 둔다고 했으니 repo root는 한 단계 위
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMUX_CONF="$REPO_ROOT/tmux/.tmux.conf"
HOOKS_ZSH="$REPO_ROOT/oh-my-zsh/custom/hooks.zsh"
NVIM_INIT="$REPO_ROOT/nvim/init.lua"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found"; }

backup() {
  local f="$1"
  [[ -f "$f" ]] || die "file not found: $f"
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
}

need uv
[[ -x "$SYS_PY" ]] || die "system python not found: $SYS_PY"

echo "==> 1) Create venv: $VENV_DIR"
if [[ ! -x "$VENV_PY" ]]; then
  uv venv "$VENV_DIR" --python "$SYS_PY"
else
  echo "    already exists: $VENV_PY"
fi

echo "==> 2) Install deps: pynvim libtmux"
uv pip install -U --python "$VENV_PY" pynvim libtmux
"$VENV_PY" -c 'import pynvim, libtmux; print("ok")' >/dev/null

echo "==> 3) Patch hardcoded python paths"

# 3-1) .tmux.conf: set -g @treemux-python-command '/usr/bin/python3'
backup "$TMUX_CONF"
perl -pi -e 's|(set\s+-g\s+@treemux-python-command\s+["'\''])(/usr/bin/python3)(["'\''])|$1.'"$VENV_PY"'.$3|g' \
  "$TMUX_CONF"

# 3-2) oh-my-zsh/custom/hooks.zsh: (/usr/bin/python3 $TMUX_PLUGIN_MANAGER_PATH/.../rename_session_windows.py &)
backup "$HOOKS_ZSH"
perl -pi -e 's|\(/usr/bin/python3\s+(\$TMUX_PLUGIN_MANAGER_PATH/tmux-window-name/scripts/rename_session_windows\.py\s*&)\)|('"$VENV_PY"' $1)|g' \
  "$HOOKS_ZSH"

# 3-3) nvim/init.lua: "/usr/bin/python3" 문자열만 교체
backup "$NVIM_INIT"
export VENV_PY

perl -0777 -pi -e 's#(vim\.(?:uv|UV)\.spawn\(\s*")/usr/bin/python3(")#$1$ENV{VENV_PY}$2#g' \
  "$NVIM_INIT"

echo "==> Done"
echo "  - Reload tmux:  tmux source-file ~/.tmux.conf"
echo "  - Reload zsh:   source ~/.zshrc"
