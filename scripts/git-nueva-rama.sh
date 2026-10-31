#!/usr/bin/env bash
# git-nueva-rama.sh (alias: git nr) - create a child branch keeping the
# feature/<HU>.<TR>.<subTR> naming so the parent is always derivable.
#   git nr <segment>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/git-flow-lib.sh"
seg="${1:?usage: git nr <segment>}"
case "$seg" in *.*|*/*) echo "[nr] segment must not contain '.' or '/': $seg" >&2; exit 1 ;; esac
cur="$(current_branch)" || { echo "[nr] detached HEAD." >&2; exit 1; }
case "$cur" in
  develop)   new="feature/$seg" ;;
  feature/*) new="$cur.$seg" ;;
  *) echo "[nr] create features from develop or another feature (now on '$cur')." >&2; exit 1 ;;
esac
valid_branch_name "$new" || { echo "[nr] invalid resulting name: $new" >&2; exit 1; }
git checkout -b "$new"
echo "[nr] created '$new' (parent: $(parent_branch "$new"))"
