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
case_sandbox squash

F=1.0.0/ot1
ORIG=$F/ORIGINAL
TST=$F/TESTING

# --- fixture: ORIGINAL already holds source a; TESTING is built on it
case_testing_tree push

# --- C1: squash of the TESTING work (one commit: its patch-id is the squash patch-id)
git checkout -q -b "$F/sq" "$ORIG"
git -c merge.ff=true merge -q --squash "$TST" || fail "C1: squash failed"
case_squash_msg "feat: squashed t1" "$CASE_REPO.msg"
out="$(git commit -q -F "$CASE_REPO.msg" 2>&1)" && fail "C1: squash of TESTING committed"
grep -q "git testing repartir" <<<"$out" && ok "C1 squash of TESTING refused at commit time" || fail "C1: squash message: $out"
# a hand-forced squash commit still carries the patch-id of the TESTING commit. why plumbing: the
# staged tree is committed with commit-tree and the branch moved with update-ref, so no hook runs;
# the squash state is cleared as git commit would clear it
sq_head="$(git rev-parse HEAD)"
sq="$(git commit-tree "$(git write-tree)" -p "$sq_head" -m "feat: squashed t1")" || fail "C1: forced squash commit"
git update-ref "refs/heads/$F/sq" "$sq" "$sq_head" || fail "C1: forced squash ref"
rm -f "$(git rev-parse --git-dir)/SQUASH_MSG"
case_refused TESTING git push origin "$F/sq"
ok "C1 squash merge of TESTING refused at push"

# --- C1: cherry-pick without -x, and with -x (what repartir writes)
git checkout -q "$TST"
case_commit t2.txt t2 "feat: t2"
t2="$(git rev-parse HEAD)"
case_commit t3.txt t3 "feat: t3"
t3="$(git rev-parse HEAD)"
git checkout -q -b "$F/cp" "$ORIG"
git cherry-pick "$t2" >/dev/null || fail "C1: cherry-pick"
case_refused TESTING git push origin "$F/cp"
ok "C1 cherry-pick without -x refused at push"
git reset -q --hard "$ORIG"
git cherry-pick -x "$t2" >/dev/null || fail "C1: cherry-pick -x"
git push -q origin "$F/cp" 2>&1 || fail "C1: cherry-pick -x refused"
ok "C1 cherry-pick -x accepted"

# --- C1: rebase of TESTING commits onto ORIGINAL
git checkout -q -b "$F/rb" "$t3"
git rebase -q --onto "$ORIG" "$t2" >/dev/null 2>&1 || fail "C1: rebase"
[ "$(git rev-parse HEAD)" != "$t3" ] || fail "C1: rebase did not rewrite"
case_refused TESTING git push origin "$F/rb"
ok "C1 rebase of TESTING commits refused at push"

# --- C1: repartir and normal work are not refused
git checkout -q "$F/a"
git testing repartir --map "$t3=$F/a" >/dev/null 2>&1 || fail "C1: repartir failed"
git push -q origin "$F/a" 2>&1 || fail "C1: push after repartir refused"
git checkout -q -b "$F/plain" "$ORIG"
case_commit plain.txt plain "feat: plain"
git push -q origin "$F/plain" 2>&1 || fail "C1: normal work refused"
ok "C1 repartir cherry-picks and normal work are not refused"
# the patch-ids are cached once per TESTING tip
tip="$(git rev-parse "$TST")"
[ -f ".git/quality-suite/tst-pids-$tip" ] && ok "C1 patch-ids cached by TESTING tip" || fail "C1: no cache"

# --- C3: squash of several TESTING commits is refused at commit time; a normal squash is not
git checkout -q -b "$F/sq3" "$ORIG"
git -c merge.ff=true merge -q --squash "$TST" || fail "C3: squash failed"
case_squash_msg "feat: squash all" "$CASE_REPO.msg"
out="$(git commit -q -F "$CASE_REPO.msg" 2>&1)" && fail "C3: squash of several TESTING commits committed"
grep -q "git testing repartir" <<<"$out" && ok "C3 squash of several TESTING commits refused" || fail "C3: message: $out"
git reset -q --hard "$ORIG"
git -c merge.ff=true merge -q --squash "$F/plain" || fail "C3: normal squash failed"
git commit -q -m "feat: squash plain" || fail "C3: normal squash refused"
ok "C3 squash of a normal branch is not refused"
git checkout -q "$F/plain"

# --- C2: a manual merge into TESTING
git checkout -q -b "$F/x" "$ORIG"
case_commit x.txt x "feat: x"
x_sha="$(git rev-parse HEAD)"
git checkout -q "$TST"
# why plumbing: the merge commit is built with merge-tree and commit-tree and the branch moved with
# update-ref (no merge hook, no reflog action); the reference-transaction hook must still see it
tst_tip="$(git rev-parse HEAD)"
mx="$(git merge-tree --write-tree "$tst_tip" "$x_sha")" || fail "C2: merge-tree of x"
mc="$(git commit-tree "$mx" -p "$tst_tip" -p "$x_sha" -m "merge x")" || fail "C2: merge commit"
out="$(git update-ref "refs/heads/$TST" "$mc" "$tst_tip" 2>&1)" || fail "C2: forced merge failed: $out"
git reset -q --hard "$mc" || fail "C2: work tree of the merge"
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
case_commit y.txt y "feat: y"
git checkout -q "$TST"
out="$(git merge --ff-only "$F/y" 2>&1)" || fail "C2: ff merge failed: $out"
grep -q "never merged into" <<<"$out" && ok "C2 a fast-forward merge into TESTING is reported" || fail "C2: ff not reported: $out"
