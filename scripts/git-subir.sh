#!/usr/bin/env bash
# git-subir.sh (alias: git subir) - rebase the current branch onto its up-to-date
# parent, then push with --force-with-lease. why: after a rebase you must
# force-push (history was rewritten); pulling would rebase again and re-show the
# same conflicts. rerere (enabled by configure_repo) reapplies past resolutions.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/git-flow-lib.sh"
cur="$(current_branch)" || { echo "[subir] detached HEAD." >&2; exit 1; }
require_clean
parent="$(parent_branch "$cur" 2>/dev/null || true)"
if [ -n "$parent" ]; then
  base="$parent"
  if git rev-parse -q --verify "refs/remotes/origin/$parent" >/dev/null 2>&1; then
    echo "[subir] fetching origin/$parent..."; git fetch -q origin "$parent" || true
    base="origin/$parent"
  fi
  if git rev-parse -q --verify "$base" >/dev/null 2>&1; then
    echo "[subir] rebasing $cur onto $base..."
    git rebase "$base" || { echo "[subir] conflicts: resolve, 'git rebase --continue', then re-run 'git subir' (rerere will remember)." >&2; exit 1; }
  fi
fi
echo "[subir] pushing $cur (--force-with-lease)..."
git push --force-with-lease origin "$cur"
echo "[subir] done."
