#!/usr/bin/env bash
# Cases of the TESTING sandbox, copies and merges (spec T6, O7):
#   C1 a squash, a cherry-pick without -x and a rebase of TESTING commits are refused at push;
#      repartir's cherry-picks (-x) and normal work are not.
#   C2 a manual merge into TESTING is reported/refused, and the merged source does not give
#      false positives (first-parent listing).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
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

# refused_push BRANCH WHY: the push must fail and mention TESTING.
# Arguments: $1 branch, $2 label for the messages. Returns: 0 when refused; fails the case otherwise.
refused_push() {
	local out
	if out="$(git push origin "$1" 2>&1)"; then fail "$2: push of $1 not refused"; fi
	grep -q "TESTING" <<<"$out" || fail "$2: refused without a TESTING message: $out"
}

# --- fixture: ORIGINAL already holds source a; TESTING is built on it
git checkout -q -b "$ORIG" develop
mk shared.txt base "chore: shared file"
git checkout -q -b "$F/a" "$ORIG"
mk a.txt a "feat: a"
git testing crear "$F/a" >/dev/null || fail "crear failed"
git checkout -q "$ORIG"
git merge -q --ff-only "$F/a" || fail "ff of ORIGINAL to a"
git push -q origin "$ORIG" "$F/a" 2>/dev/null || fail "push of ORIGINAL and a"
git checkout -q "$TST"
mk t1.txt t1 "feat: t1"

# --- C1: squash of the TESTING work (one commit: its patch-id is the squash patch-id)
git checkout -q -b "$F/sq" "$ORIG"
git -c merge.ff=true merge -q --squash "$TST" || fail "C1: squash failed"
git commit -q -m "feat: squashed t1" || fail "C1: squash commit"
refused_push "$F/sq" "C1 squash"
ok "C1 squash merge of TESTING refused at push"

# --- C1: cherry-pick without -x, and with -x (what repartir writes)
git checkout -q "$TST"
mk t2.txt t2 "feat: t2"
t2="$(git rev-parse HEAD)"
mk t3.txt t3 "feat: t3"
t3="$(git rev-parse HEAD)"
git checkout -q -b "$F/cp" "$ORIG"
git cherry-pick "$t2" >/dev/null || fail "C1: cherry-pick"
refused_push "$F/cp" "C1 cherry-pick"
ok "C1 cherry-pick without -x refused at push"
git reset -q --hard "$ORIG"
git cherry-pick -x "$t2" >/dev/null || fail "C1: cherry-pick -x"
git push -q origin "$F/cp" 2>&1 || fail "C1: cherry-pick -x refused"
ok "C1 cherry-pick -x accepted"

# --- C1: rebase of TESTING commits onto ORIGINAL
git checkout -q -b "$F/rb" "$t3"
git rebase -q --onto "$ORIG" "$t2" >/dev/null 2>&1 || fail "C1: rebase"
[ "$(git rev-parse HEAD)" != "$t3" ] || fail "C1: rebase did not rewrite"
refused_push "$F/rb" "C1 rebase"
ok "C1 rebase of TESTING commits refused at push"

# --- C1: repartir and normal work are not refused
git checkout -q "$F/a"
git testing repartir --map "$t3=$F/a" >/dev/null 2>&1 || fail "C1: repartir failed"
git push -q origin "$F/a" 2>&1 || fail "C1: push after repartir refused"
git checkout -q -b "$F/plain" "$ORIG"
mk plain.txt plain "feat: plain"
git push -q origin "$F/plain" 2>&1 || fail "C1: normal work refused"
ok "C1 repartir cherry-picks and normal work are not refused"
# the patch-ids are cached once per TESTING tip
tip="$(git rev-parse "$TST")"
[ -f ".git/quality-suite/tst-pids-$tip" ] && ok "C1 patch-ids cached by TESTING tip" || fail "C1: no cache"

# --- C2: a manual merge into TESTING
git checkout -q -b "$F/x" "$ORIG"
mk x.txt x "feat: x"
x_sha="$(git rev-parse HEAD)"
git checkout -q "$TST"
out="$(git merge --no-verify --no-ff -m "merge x" "$F/x" 2>&1)" || fail "C2: forced merge failed: $out"
grep -q "never merged into" <<<"$out" && ok "C2 reference-transaction reports the merge into TESTING" || fail "C2: no report: $out"
out="$(git testing estado 2>&1)" || true
grep -q "feat: x" <<<"$out" && fail "C2: merged source commit listed as made on TESTING: $out"
ok "C2 first-parent listing ignores merged sources"
out="$(git push origin "$TST" 2>&1)" && fail "C2: TESTING with a merge was pushed"
grep -q "git testing crear --recrear" <<<"$out" && ok "C2 pre-push refuses a TESTING with a merge" || fail "C2: push message: $out"
git checkout -q "$F/x"
out="$(git push origin "$F/x" 2>&1)" || fail "C2: the merged source gives a false positive: $out"
ok "C2 the merged source can still be pushed"
[ "$(git rev-parse "$F/x")" = "$x_sha" ] || fail "C2: x moved"

# --- C2: a fast-forward merge into TESTING
git checkout -q -b "$F/y" "$TST"
mk y.txt y "feat: y"
git checkout -q "$TST"
out="$(git merge --ff-only "$F/y" 2>&1)" || fail "C2: ff merge failed: $out"
grep -q "never merged into" <<<"$out" && ok "C2 a fast-forward merge into TESTING is reported" || fail "C2: ff not reported: $out"
