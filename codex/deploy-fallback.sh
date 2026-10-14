#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
commit="$(git -C "$repo_dir" rev-parse HEAD)"
if [[ $# -eq 0 ]]; then
  printf 'Usage: %s SSH_HOST [SSH_HOST ...]\nPush the desired commit to origin/main before deploying.\n' "$0" >&2
  exit 2
fi

for host in "$@"; do
  printf '[codex-fallback] Deploying %s to %s\n' "$commit" "$host"
  ssh -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 "$host" bash -s -- "$commit" <<'REMOTE'
set -euo pipefail
commit="$1"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
export PATH="$HOME/.local/bin:$PATH"
repo_dir="$HOME/dotfiles"
if [[ ! -e "$repo_dir" ]]; then
  git clone git@github.com:hslyu/dotfiles "$repo_dir"
fi
git -C "$repo_dir" fetch origin
git -C "$repo_dir" merge-base --is-ancestor "$commit" origin/main
release_dir="$HOME/.local/share/dotfiles-codex-releases/$commit"
if [[ ! -e "$release_dir" ]]; then
  mkdir -p "$(dirname "$release_dir")"
  git -C "$repo_dir" worktree add --detach "$release_dir" "$commit"
fi
[[ "$(git -C "$release_dir" rev-parse HEAD)" == "$commit" ]]
bash "$release_dir/codex/install-fallback.sh"
"$HOME/.local/bin/codex" --version
"$HOME/.local/bin/codex-personal" --version
printf '[codex-fallback] Deployed %s on %s (existing dotfiles changes preserved)\n' "$commit" "$(hostname)"
REMOTE
done
