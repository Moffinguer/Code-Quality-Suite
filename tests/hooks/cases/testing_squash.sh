#!/usr/bin/env bash
# Cases of the squash guard (commit-msg, testing_squash_hit): the squash commit of TESTING work is
# refused; a .git/SQUASH_MSG left by an aborted squash is stale: an unrelated commit goes through
# and a one-line note says the file can be deleted (S1).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox merge

F=1.0.0/ot1
ORIG=$F/ORIGINAL
TST=$F/TESTING

# mk FILE CONTENT SUBJECT: write FILE, commit it on the current branch.
# Arguments: $1 file, $2 content, $3 commit subject. Returns: 0; exits 1 through fail on error.
mk() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -q -m "$3" || fail "commit '$3' on $(git branch --show-current)"
}

# squash_msg SUBJECT FILE: write the message git proposes for the pending squash (SQUASH_MSG),
# under SUBJECT, into FILE. Arguments: $1 subject, $2 file. Returns: 0; fails the case otherwise.
squash_msg() {
	{
		printf '%s\n\n' "$1"
		cat .git/SQUASH_MSG
	} >"$2" || fail "cannot write the squash message"
}

# --- fixture: an ORIGINAL, a TESTING built on it with one commit of its own
git checkout -q -b "$ORIG" develop
mk shared.txt base "chore: shared file"
git checkout -q -b "$F/a" "$ORIG"
mk a.txt a "feat: a"
git testing crear "$F/a" >/dev/null || fail "S1: crear failed"
git checkout -q "$TST"
mk t1.txt t1 "feat: t1"

# --- S1: squash of the TESTING work, then aborted: the file is left behind
git checkout -q -b "$F/sq" "$ORIG"
git -c merge.ff=true merge -q --squash "$TST" || fail "S1: squash failed"
git restore --source=HEAD --staged --worktree :/ || fail "S1: abort failed"
[ -f .git/SQUASH_MSG ] || fail "S1: the aborted squash left no SQUASH_MSG"
ok "S1 an aborted squash leaves .git/SQUASH_MSG behind"

# --- S1: an unrelated commit is accepted; the stale file is named in a one-line note
printf 'x\n' >x.txt
git add x.txt
out="$(git commit -q -m "feat: x" 2>&1)" || fail "S1: unrelated commit refused: $out"
[ "$(git log -n1 --format=%s)" = "feat: x" ] || fail "S1: unrelated commit not made"
grep -q "SQUASH_MSG is stale" <<<"$out" && ok "S1 unrelated commit accepted, stale file noted" ||
	fail "S1: no stale note: $out"

# --- S1: the squash commit itself is still refused, when it uses the proposed message
git -c merge.ff=true merge -q --squash "$TST" || fail "S1: second squash failed"
squash_msg "feat: squashed t1" "$CASE_REPO.msg"
out="$(git commit -q -F "$CASE_REPO.msg" 2>&1)" && fail "S1: squash of TESTING committed"
grep -q "git testing repartir" <<<"$out" && ok "S1 the squash commit is refused" || fail "S1: squash message: $out"
