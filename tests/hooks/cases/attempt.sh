#!/usr/bin/env bash
# Cases of the ATTEMPT branches (6.0.0 agents/attempt_branch): the alias name decides the command
# (AT0), git intentos creates the structure and the worktrees (AT1), git elegir compares and waits
# for a person (AT2), squashes the chosen attempt with Chosen-from and cleans up (AT3), and refuses
# an attempt with pending children (AT4).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

OT=6.0.0/ot1
TASK=$OT/a
ORIG=$TASK/ORIGINAL

# the aliases: each call names the alias it stands for, as configure_repo does through QS_ALIAS
intentos() { QS_ALIAS=intentos git intentos "$@"; }
elegir() { QS_ALIAS=elegir git elegir "$@"; }

# fixture: version and OT parents, and a task with one commit (made with plumbing, no hooks)
git branch 6.0.0/ORIGINAL develop
git branch $OT/ORIGINAL develop
git branch "$TASK" $OT/ORIGINAL
plumb_commit local "$TASK" a.txt base "feat: base of a" >/dev/null

# --- AT0: the alias name decides; 'elegir' with two arguments is refused with the usage (exit 2)
rc=0
out="$(QS_ALIAS=elegir git elegir b 2 2>&1)" || rc=$?
[ "$rc" = 2 ] && grep -q '^usage: ' <<<"$out" && [ -z "$(git for-each-ref refs/heads/b/)" ] && ok "AT0: git elegir b 2 is refused with the usage" || fail "AT0: rc=$rc out=$out"
rc=0
out="$(QS_ALIAS=bogus git intentos "$TASK" 2 2>&1)" || rc=$?
[ "$rc" = 2 ] && grep -q '^usage: ' <<<"$out" && ok "AT0: an unknown alias name prints the usage (exit 2)" || fail "AT0: unknown name rc=$rc out=$out"

# --- AT1: the structure and one worktree per attempt
intentos "$TASK" 3 >/dev/null || fail "AT1: git intentos failed"
git show-ref --verify -q "refs/heads/$ORIG" && ! git show-ref --verify -q "refs/heads/$TASK" && ok "AT1: the task became its ORIGINAL" || fail "AT1: rename"
for i in 1 2 3; do
	git show-ref --verify -q "refs/heads/$TASK/ATTEMPT-$i" || fail "AT1: ATTEMPT-$i missing"
	git worktree list --porcelain | grep -qx "branch refs/heads/$TASK/ATTEMPT-$i" || fail "AT1: no worktree for ATTEMPT-$i"
done
ok "AT1: ATTEMPT-1..3 exist, each in a worktree"
! intentos "$TASK" 2 >/dev/null 2>&1 && ok "AT1: a second git intentos is refused" || fail "AT1: repeated intentos"
! intentos "$OT/zz" 0 >/dev/null 2>&1 && ok "AT1: N=0 is refused" || fail "AT1: N=0"

# the attempts: 1 fails the tests, 2 passes (small), 3 passes (bigger)
T1="$TASK/ATTEMPT-1" T2="$TASK/ATTEMPT-2" T3="$TASK/ATTEMPT-3"
plumb_commit local "$T1" .quality-tests "test -f ok.txt" "test: tests of attempt 1" >/dev/null
plumb_commit local "$T2" .quality-tests "test -f ok.txt" "test: tests of attempt 2" >/dev/null
plumb_commit local "$T2" ok.txt two "feat: attempt 2" >/dev/null
plumb_commit local "$T3" .quality-tests "test -f ok.txt" "test: tests of attempt 3" >/dev/null
plumb_commit local "$T3" ok.txt three "feat: attempt 3" >/dev/null
plumb_commit local "$T3" extra.txt "$(seq 1 20)" "feat: more in attempt 3" >/dev/null
before="$(git rev-parse "$ORIG")"

# --- AT2: table and proposal; waiting; n changes nothing; --auto refused
out="$(printf 'n\n' | elegir "$TASK" 2>&1)" && fail "AT2: n must not succeed"
grep -q 'ATTEMPT-2' <<<"$out" && grep -q 'Proposal: ATTEMPT-2' <<<"$out" && ok "AT2: the table and the proposal (the passing, smaller attempt)" || fail "AT2: output: $out"
grep -qE 'ATTEMPT-1 +[^ ]+ +FAIL' <<<"$out" && ok "AT2: a failing test run is shown" || fail "AT2: no FAIL row: $out"
[ "$(git rev-parse "$ORIG")" = "$before" ] && git show-ref --verify -q "refs/heads/$T1" && ok "AT2: n changed nothing" || fail "AT2: n changed something"
! elegir "$TASK" </dev/null >/dev/null 2>&1 && [ "$(git rev-parse "$ORIG")" = "$before" ] && ok "AT2: no answer changed nothing" || fail "AT2: empty answer"
out="$(elegir --auto "$TASK" 2>&1)" && fail "AT2: --auto must be refused"
grep -q 'always needs a person' <<<"$out" && ok "AT2: --auto is refused" || fail "AT2: --auto message: $out"

# --- AT4: an attempt that became a parent with a pending child is refused
git branch "$T3/ORIGINAL" "$T3" 2>/dev/null && fail "AT4: a ref clash was expected" || true
git worktree remove --force "$(git worktree list --porcelain | awk -v b="branch refs/heads/$T3" '$1=="worktree"{w=substr($0,10)} $0==b{print w}')"
git branch -m "$T3" "$T3/ORIGINAL"
git branch "$T3/child" "$T3/ORIGINAL"
out="$(elegir "$T3/ORIGINAL" 2>&1)" && fail "AT4: must be refused"
grep -q 'children pending' <<<"$out" && ok "AT4: ATTEMPT-3/ORIGINAL with a pending child is refused (by name)" || fail "AT4: $out"
out="$(printf 'y\n' | elegir "$TASK" 2>&1)" && fail "AT4: the task must be refused too"
grep -q 'children pending' <<<"$out" && [ "$(git rev-parse "$ORIG")" = "$before" ] && ok "AT4: git elegir <task> refuses and changes nothing" || fail "AT4: $out"
git branch -D "$T3/child" >/dev/null

# --- AT3: confirming attempt 2
out="$(printf '2\n' | elegir "$TASK" 2>&1)" || fail "AT3: elegir failed: $out"
[ "$(git rev-list --count "$before..$ORIG")" = 1 ] && [ "$(git log -1 --format=%p "$ORIG" | wc -w)" = 1 ] && ok "AT3: ONE single-parent commit on the ORIGINAL" || fail "AT3: not one commit"
msg="$(git log -1 --format=%B "$ORIG")"
grep -qx 'Chosen-from: ATTEMPT-2' <<<"$msg" && grep -q 'ATTEMPT-1: gate findings' <<<"$msg" && grep -q '^Commits:' <<<"$msg" && grep -q '^Files:' <<<"$msg" && grep -q '^Refs: ' <<<"$msg" && grep -q '^Squashed: ' <<<"$msg" && ok "AT3: trailers and the comparison are in the message" || fail "AT3: message: $msg"
[ "$(git show "$ORIG:ok.txt")" = two ] && ! git cat-file -e "$ORIG:extra.txt" 2>/dev/null && ok "AT3: the content is attempt 2's" || fail "AT3: content"
left="$(git for-each-ref "refs/heads/$TASK/ATTEMPT-*" "refs/heads/$T3/*" | wc -l)"
[ "$left" = 0 ] && ! git worktree list | grep -q 'ATTEMPT' && ok "AT3: the attempts and their worktrees are gone" || fail "AT3: leftovers ($left)"
grep -q 'deleted ATTEMPT-1 .*tip [0-9a-f]\{40\}' <<<"$out" && ok "AT3: the tips are printed" || fail "AT3: tips: $out"
