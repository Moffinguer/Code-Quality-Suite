#!/usr/bin/env bash
# Cases of the REVIEW branch (6.0.0 agents/review_branch task, RV1-RV4): git revision creates
# <node>/REVIEW-<task>, --aplicar cherry-picks proposals, --descartar deletes it.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

A=6.0.0/ot1/a
R=6.0.0/ot1/REVIEW-a
git branch 6.0.0/ot1/ORIGINAL develop
git branch "$A" develop
git push -q origin 6.0.0/ot1/ORIGINAL "$A" 2>/dev/null || fail "push the task branches"

# rev ARGS...: run git revision (the suite script) with ARGS. Returns: its status.
rev() { bash "$SUITE/scripts/git-revision.sh" "$@"; }

# --- RV1 creation
rev "$A" >/dev/null 2>&1 || fail "RV1: git revision $A"
[ "$(git rev-parse "$R")" = "$(git rev-parse "$A")" ] && ok "RV1 $R created at the tip of $A" || fail "RV1: tip"
! rev "$A" >/dev/null 2>&1 && ok "RV1 a second git revision is refused" || fail "RV1: duplicate accepted"
! rev 6.0.0/ot1/ORIGINAL >/dev/null 2>&1 && ! rev "$R" >/dev/null 2>&1 && ok "RV1 ORIGINAL and REVIEW are no tasks" || fail "RV1: bad task accepted"
! rev 6.0.0/ot1/nope >/dev/null 2>&1 && ok "RV1 unknown task refused" || fail "RV1: unknown task accepted"

# --- RV2 proposals
c1="$(plumb_commit local "$R" f1.txt one "chore: proposal one")"
c2="$(plumb_commit local "$R" f2.txt two "chore: proposal two")"
git switch -q "$A"
! rev --aplicar "$(git rev-parse develop)" >/dev/null 2>&1 && ok "RV2 a commit that is no proposal is refused" || fail "RV2: foreign commit accepted"
rev --aplicar "$c1" >/dev/null 2>&1 || fail "RV2: --aplicar c1"
[ -f f1.txt ] && [ ! -f f2.txt ] && git log -n1 --format=%B | grep -q "cherry picked from commit $c1" &&
	ok "RV2 --aplicar <c1> brings only c1 (cherry-pick -x)" || fail "RV2: only c1"
[ "$(git rev-parse "$R")" = "$c2" ] && ok "RV2 REVIEW is untouched" || fail "RV2: REVIEW moved"
rev --aplicar >/dev/null 2>&1 || fail "RV2: --aplicar all"
[ -f f2.txt ] && ok "RV2 --aplicar without commits applies every proposal" || fail "RV2: all"
rev --descartar >/dev/null 2>&1 || fail "RV2: --descartar"
! git rev-parse -q --verify "refs/heads/$R" >/dev/null && ! git rev-parse -q --verify "refs/remotes/origin/$R" >/dev/null &&
	ok "RV2 --descartar deletes REVIEW" || fail "RV2: not deleted"
! rev --descartar >/dev/null 2>&1 && ok "RV2 --descartar without REVIEW is refused" || fail "RV2: discard of nothing"

# --- RV3/RV4 need the integra_order branch (git subir / git integra rules for REVIEW)
if grep -q "REVIEW" "$SUITE/hooks/pre-merge-commit" 2>/dev/null; then
	rev "$A" >/dev/null 2>&1 || fail "RV3: git revision again"
	plumb_commit local "$A" g.txt moved "chore: a moved" >/dev/null
	git switch -q "$R"
	git subir >/dev/null 2>&1 || fail "RV3: git subir on REVIEW"
	git merge-base --is-ancestor "$A" "$R" && ok "RV3 git subir rebases REVIEW onto the task" || fail "RV3: not rebased"
	git switch -q 6.0.0/ot1/ORIGINAL
	! git merge --no-ff "$R" >/dev/null 2>&1 && ok "RV4 merging REVIEW into an ORIGINAL is refused" || fail "RV4: merge accepted"
else
	ok "RV3/RV4 left to integra_order (git subir and git integra rules are not in this branch)"
fi
