#!/usr/bin/env bash
# Cases of the OT release with special leftovers (6.0.0 on_release = delete): a local CHECKPOINT is
# never pushed nor set aside; REVIEW, QUARANTINE and SPIKE are deleted (on origin too, when they were
# published) with one restore line each; the preview lists them; a normal task is still set aside.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

V=6.0.0
OT=$V/ot1
git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "version tree"
git np ot1 >/dev/null || fail "OT ORIGINAL"
git nr first >/dev/null || fail "nr done"
printf 'one\n' >a.txt
git add a.txt
git commit -q -m "feat(a): add a" || fail "commit on first"
git integra --yes -m "feat(ot1): add a" >/dev/null 2>&1 || fail "integra first"
git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push the OT ORIGINAL"
tip="$(git rev-parse "$OT/ORIGINAL")"

# leftovers: a CHECKPOINT only local, the others pushed, plus a normal task with a commit of its own
git branch "$OT/CHECKPOINT-t1" "$tip"
for n in REVIEW-t1 QUARANTINE-t1; do git branch "$OT/$n" "$tip"; done
git branch "$OT/SPIKE" "$tip"
git checkout -q -b "$OT/open" "$tip"
printf 'two\n' >b.txt
git add b.txt
git commit -q -m "feat(b): add b" || fail "commit on open"
git checkout -q "$OT/ORIGINAL"
for n in REVIEW-t1 QUARANTINE-t1 SPIKE open; do git push -q origin "$OT/$n" 2>/dev/null || fail "push $n"; done
sha_ck="$(git rev-parse "$OT/CHECKPOINT-t1")"
sha_sp="$(git rev-parse "$OT/SPIKE")"

# --- SR1 the preview lists what will be deleted and changes nothing
out="$(git changelog --ot "$OT" 2>&1)" || true
for n in CHECKPOINT-t1 REVIEW-t1 QUARANTINE-t1 SPIKE; do
	grep -q "$OT/$n: .* will be deleted" <<<"$out" && ok "SR1: the preview lists $n as deleted" || fail "SR1: $n not listed: $out"
done
git show-ref --verify -q "refs/heads/$OT/CHECKPOINT-t1" && ok "SR1: the preview deleted nothing" || fail "SR1: preview deleted a branch"

# --- SR2 the release
out="$(git release --ot "$OT" --yes 2>&1)" || fail "SR2: OT release: $out"
git for-each-ref --format='%(refname)' | grep -q "CHECKPOINT" && fail "SR2: a CHECKPOINT ref is left (local, origin or unmerged)" ||
	ok "SR2: a local CHECKPOINT is not archived and never pushed"
[ -z "$(git ls-remote origin '*CHECKPOINT*')" ] && ok "SR2: origin has no CHECKPOINT" || fail "SR2: CHECKPOINT on origin"
grep -q "CHECKPOINT-t1, was at $sha_ck: git branch $OT/CHECKPOINT-t1 $sha_ck" <<<"$out" &&
	ok "SR2: the restore line of the CHECKPOINT is printed" || fail "SR2: no restore line: $out"
grep -q "SPIKE, was at $sha_sp: git branch $OT/SPIKE $sha_sp" <<<"$out" && ok "SR2: the restore line of the SPIKE is printed" ||
	fail "SR2: no SPIKE restore line: $out"
for n in REVIEW-t1 QUARANTINE-t1 SPIKE; do
	git show-ref --verify -q "refs/heads/$OT/$n" && fail "SR2: $n kept locally"
	[ -z "$(git ls-remote origin "refs/heads/$OT/$n")" ] || fail "SR2: $n kept on origin"
	git show-ref | grep -q "unmerged/.*$n" && fail "SR2: $n set aside"
	grep -q "$OT/$n, was at" <<<"$out" || fail "SR2: no restore line for $n"
done
ok "SR2: REVIEW, QUARANTINE and SPIKE are deleted locally and on origin with a restore line"
git show-ref --verify -q "refs/heads/unmerged/$OT/open" && [ -n "$(git ls-remote origin "refs/heads/unmerged/$OT/open")" ] &&
	ok "SR2: a normal unintegrated task is still set aside" || fail "SR2: open not set aside"
