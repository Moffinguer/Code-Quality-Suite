#!/usr/bin/env bash
# git arbol --limpiar (scripts/git-rama.sh), 7.1.1/cleanup/arbol_fix: a parent ORIGINAL whose two
# children are integrated is cleaned in ONE run together with its children (it used to need two).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

V=9.2.0 OT="$V/700"
RF="$OT/RF3"

# local_has BRANCH: succeed when the local branch exists.
local_has() { git rev-parse -q --verify "refs/heads/$1" >/dev/null; }

# on_origin BRANCH: succeed when the branch exists on origin.
on_origin() { [ -n "$(git ls-remote --heads origin "refs/heads/$1")" ]; }

# add_child NAME: create the final branch NAME under $RF/ORIGINAL with one commit, push it,
# integrate it and push it again (local and origin copies). Exits through fail on any error.
add_child() {
	git nr "$1" >/dev/null || fail "nr $1"
	printf '%s = 1\n' "$1" >"$1.py"
	git add "$1.py"
	git commit -q -m "feat: add $1" || fail "commit $1"
	git push -q origin "$RF/$1" 2>/dev/null || fail "push $1"
	git integra -m "feat: integrate $1" -m "why $1" >/dev/null 2>&1 </dev/null || fail "integra $1"
	QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$RF/$1" 2>/dev/null || fail "repush $1"
	git checkout -q "$RF/ORIGINAL"
}

# --- AB1 one run deletes the parent ORIGINAL and its two integrated children, the second says nothing
case_sandbox squash
git np "$V" >/dev/null && git np 700 >/dev/null && git np RF3 >/dev/null || fail "tree $RF"
add_child a
add_child b
QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$RF/ORIGINAL" 2>/dev/null || fail "push RF ORIGINAL"
git integra -m "feat: integrate RF3" -m "why RF3" >/dev/null 2>&1 </dev/null || fail "integra RF3"
git checkout -q "$OT/ORIGINAL"
QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push OT ORIGINAL"
git fetch -q origin
for b in ORIGINAL a b; do
	local_has "$RF/$b" && on_origin "$RF/$b" || fail "AB1 fixture: $RF/$b"
done
OUT1="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "AB1 run 1 failed: $OUT1"
GONE=1
for b in ORIGINAL a b; do
	! local_has "$RF/$b" && ! on_origin "$RF/$b" || GONE=0
done
[ "$GONE" = 1 ] && ok "AB1 run 1 deleted the parent ORIGINAL and both children, local and origin" ||
	fail "AB1 run 1: $OUT1"
OUT2="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "AB1 run 2 failed: $OUT2"
grep -q "nothing to clean" <<<"$OUT2" && ok "AB1 run 2 has nothing left to clean" || fail "AB1 run 2: $OUT2"

# --- AB1b the same tree, but the children live only on origin and the local parent is behind origin
# (the origin copies are integrated in origin/<parent>; the local parent lacks their squash commits)
case_sandbox squash
git np "$V" >/dev/null && git np 700 >/dev/null && git np RF3 >/dev/null || fail "AB1b tree $RF"
BASE="$(git rev-parse "$RF/ORIGINAL")"
add_child a
add_child b
QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$RF/ORIGINAL" 2>/dev/null || fail "AB1b push RF ORIGINAL"
git integra -m "feat: integrate RF3" -m "why RF3" >/dev/null 2>&1 </dev/null || fail "AB1b integra RF3"
git checkout -q "$OT/ORIGINAL"
QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "AB1b push OT ORIGINAL"
git branch -q -D "$RF/a" "$RF/b" || fail "AB1b drop the local children"
git update-ref "refs/heads/$RF/ORIGINAL" "$BASE"
git fetch -q origin
OUT1="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "AB1b run 1 failed: $OUT1"
GONE=1
for b in ORIGINAL a b; do
	! local_has "$RF/$b" && ! on_origin "$RF/$b" || GONE=0
done
[ "$GONE" = 1 ] && ok "AB1b run 1 deleted the parent ORIGINAL and both origin-only children" ||
	fail "AB1b run 1: $OUT1"
OUT2="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "AB1b run 2 failed: $OUT2"
grep -q "nothing to clean" <<<"$OUT2" && ok "AB1b run 2 has nothing left to clean" || fail "AB1b run 2: $OUT2"
