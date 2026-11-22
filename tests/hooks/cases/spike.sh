#!/usr/bin/env bash
# Cases of the SPIKE special branch (6.0.0 spike_branch task): git spike and git spike --llevar.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash
export QS_PUBLISH=0

git np 6.0.0 >/dev/null
git np ot1 >/dev/null

# --- SP1 git spike
out="$(git spike 2>&1)" || fail "git spike on the OT ORIGINAL: $out"
[ "$(git branch --show-current)" = 6.0.0/ot1/SPIKE ] && [ "$(git rev-parse 6.0.0/ot1/SPIKE)" = "$(git rev-parse 6.0.0/ot1/ORIGINAL)" ] &&
	ok "git spike creates <node>/SPIKE at the ORIGINAL" || fail "SPIKE not created: $out"
git checkout -q 6.0.0/ot1/ORIGINAL
out="$(git spike 2>&1)" && fail "a second SPIKE was created"
grep -q "already has a SPIKE" <<<"$out" && ok "a second SPIKE of the node is refused" || fail "second SPIKE: $out"
git checkout -q 6.0.0/ORIGINAL
out="$(git spike 2>&1)" && fail "git spike at version level"
ok "git spike at the version level is refused"
git checkout -q develop
out="$(git spike 2>&1)" && fail "git spike on develop"
ok "git spike outside an ORIGINAL is refused"
git checkout -q 6.0.0/ot1/SPIKE
git convertir-padre --yes >/dev/null 2>&1 || fail "convertir-padre on SPIKE"
git show-ref --verify -q refs/heads/6.0.0/ot1/SPIKE/ORIGINAL && ok "git convertir-padre gives SPIKE/ORIGINAL" || fail "SPIKE/ORIGINAL missing"
git checkout -q 6.0.0/ot1/SPIKE/ORIGINAL
git nr cache >/dev/null || fail "git nr inside SPIKE/ORIGINAL"
git show-ref --verify -q refs/heads/6.0.0/ot1/SPIKE/cache && ok "children live inside SPIKE/ORIGINAL" || fail "child of SPIKE missing"

# --- SP2 git spike --llevar
orig="$(git rev-parse 6.0.0/ot1/ORIGINAL)"
c1="$(plumb_commit local 6.0.0/ot1/SPIKE/cache a.txt one 'feat: add a')"
c2="$(plumb_commit local 6.0.0/ot1/SPIKE/cache b.txt two 'fix: add b')"
git checkout -q 6.0.0/ot1/ORIGINAL
out="$(git spike --llevar 6.0.0/ot1/SPIKE/cache t1 2>&1)" || fail "--llevar: $out"
[ "$(git rev-parse 6.0.0/ot1/ORIGINAL)" = "$orig" ] && [ "$(git branch --show-current)" = 6.0.0/ot1/ORIGINAL ] || fail "ORIGINAL or checkout moved"
[ "$(git rev-list --count "$orig..6.0.0/ot1/t1")" = 2 ] && [ "$(git rev-parse 6.0.0/ot1/t1~2)" = "$orig" ] &&
	ok "--llevar creates <node>/t1 from ORIGINAL with the two spike commits" || fail "t1 history"
msgs="$(git log --format=%B "$orig..6.0.0/ot1/t1")"
grep -q "^Spike-of: 6.0.0/ot1/SPIKE/cache $c1\$" <<<"$msgs" && grep -q "^Spike-of: 6.0.0/ot1/SPIKE/cache $c2\$" <<<"$msgs" &&
	ok "each commit has Spike-of: <branch> <sha>" || fail "trailers: $msgs"
[ "$(git show 6.0.0/ot1/t1:a.txt)" = one ] && [ "$(git show 6.0.0/ot1/t1:b.txt)" = two ] && ok "the content came over" || fail "content"
[ "$(git log -n1 --format=%an 6.0.0/ot1/t1)" = tester ] && ok "author kept" || fail "author"

# a name that is taken, reserved or not a SPIKE branch is refused
out="$(git spike --llevar 6.0.0/ot1/SPIKE/cache t1 2>&1)" && fail "taken name accepted"
grep -q "already exists" <<<"$out" && ok "an existing task name is refused" || fail "taken: $out"
out="$(git spike --llevar 6.0.0/ot1/t1 t2 2>&1)" && fail "non-spike branch accepted"
grep -q "not a SPIKE branch" <<<"$out" && ok "a branch outside SPIKE is refused" || fail "non-spike: $out"
out="$(git spike --llevar 6.0.0/ot1/SPIKE/cache docs 2>&1)" && fail "reserved name accepted"
grep -q "reserved" <<<"$out" && ok "a reserved task name is refused" || fail "reserved: $out"
out="$(git spike --llevar 6.0.0/ot1/SPIKE/ORIGINAL t3 2>&1)" && fail "spike without commits accepted"
grep -q "no commits of its own" <<<"$out" && ok "a SPIKE without own commits is refused" || fail "no commits: $out"

# a conflict stops and leaves no half branch
git branch -q --no-track 6.0.0/ot1/SPIKE/other 6.0.0/ot1/SPIKE/ORIGINAL
plumb_commit local 6.0.0/ot1/ORIGINAL a.txt base 'feat: base a' >/dev/null
plumb_commit local 6.0.0/ot1/SPIKE/other a.txt spike 'feat: a in the spike' >/dev/null
out="$(git spike --llevar 6.0.0/ot1/SPIKE/other t4 2>&1)" && fail "conflict accepted: $out"
grep -q "conflict" <<<"$out" && ! git show-ref --verify -q refs/heads/6.0.0/ot1/t4 && ok "a conflict stops and leaves no branch" || fail "conflict: $out"
