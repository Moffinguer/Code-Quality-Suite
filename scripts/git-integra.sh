#!/usr/bin/env bash
# git-integra.sh (alias: git integra) - integrate the current feature branch into
# its parent in one shot: rebase onto parent, then squash-merge (nested) or
# --no-ff merge (into develop), composing a Conventional-Commits message from the
# new commits + file manifest. Short/long description are filled in the editor.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/git-flow-lib.sh"
configure_repo "$(cd "$DIR/.." && pwd)"  # force alias/config to exist even if never installed

cur="$(current_branch)" || { echo "[integra] detached HEAD." >&2; exit 1; }
valid_branch_name "$cur" || { echo "[integra] '$cur' is not a valid branch name." >&2; exit 1; }
parent="$(parent_branch "$cur")"
[ -n "$parent" ] || { echo "[integra] '$cur' has no parent to integrate into." >&2; exit 1; }
git show-ref --verify -q "refs/heads/$parent" || { echo "[integra] parent '$parent' does not exist locally." >&2; exit 1; }
require_clean

into="merge --squash"; [ "$parent" = develop ] && into="merge --no-ff"
echo "[integra] $cur  ->  $parent   (rebase, then $into)"
git rebase "$parent" || { echo "[integra] rebase conflicts; resolve, 'git rebase --continue', then re-run." >&2; exit 1; }

leaf="$(leaf_segment "$cur")"; story="$(story_segment "$cur")"
commits="$(git log --reverse --format='- %h %s' "$parent..$cur" || true)"
manifest="$(git diff --name-status "$parent...$cur" || true)"

tpl="$(mktemp)"
{
  echo "feat($leaf): DESCRIPCION_BREVE"
  echo ""
  echo "DESCRIPCION_DETALLADA (TR $leaf de la historia $story)"
  echo ""
  echo "Refs: $story"
  echo ""
  echo "Commits:"; printf '%s\n' "$commits"
  echo ""
  echo "Files:"; printf '%s\n' "$manifest"
  echo ""
  echo "# Fill the subject and the two DESCRIPCION_* lines. '#' lines are removed."
} > "$tpl"

editor="${GIT_EDITOR:-$(git config core.editor 2>/dev/null || echo "${EDITOR:-vi}")}"
$editor "$tpl"
subject="$(grep -vE '^[[:space:]]*#' "$tpl" | grep -vE '^[[:space:]]*$' | head -n1 || true)"
case "$subject" in *DESCRIPCION_BREVE*|"") echo "[integra] subject not filled in; aborted." >&2; rm -f "$tpl"; exit 1 ;; esac

git checkout "$parent"
if [ "$parent" = "develop" ]; then
  git merge --no-ff --no-commit "$cur" || { echo "[integra] conflicts on develop; resolve, then: git commit -F '$tpl' --cleanup=strip" >&2; exit 1; }
else
  git -c merge.ff=true merge --squash "$cur"
fi
git commit --cleanup=strip -F "$tpl"
rm -f "$tpl"
echo "[integra] done: '$cur' integrated into '$parent'."
