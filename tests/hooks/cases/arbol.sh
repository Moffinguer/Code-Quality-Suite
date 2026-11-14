#!/usr/bin/env bash
# git arbol (scripts/git-rama.sh), 5.0.0-RC1/git/arbol: with branches.flow = squash it reads the
# Refs:/Squashed: trailers like git integra (an integrated branch shows "= integrated as <sha>"),
# marks TESTING (with its sources), the OT and version RELEASE and unmerged/...; git arbol
# --limpiar deletes the integrated branches (locally and on origin) and keeps an ORIGINAL with
# pending children, a RELEASE, a TESTING and a branch checked out in a worktree. flow = merge
# prints what 4.x printed.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# add_commit FILE TEXT SUBJECT: write TEXT into FILE and commit it on the current branch.
# Exits through fail when the commit is refused.
add_commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -q -m "$3" || fail "commit $3"
}

# integrate_keep BRANCH FILE: on BRANCH commit FILE, push it, integrate it into its ORIGINAL (no
# --yes and no terminal: the branch is kept) and push the rebased branch back to origin, so that
# it exists on both sides like a branch that was not cleaned yet.
integrate_keep() {
	git checkout -q "$RF/ORIGINAL" && git nr "$1" >/dev/null || fail "nr $1"
	add_commit "$2" "V = 1" "feat: add $1"
	git push -q origin "$RF/$1" 2>/dev/null || fail "push $1"
	git integra -m "feat: integrate $1" -m "why $1" >/dev/null 2>&1 </dev/null || fail "integra $1"
	git rev-parse -q --verify "refs/heads/$RF/$1" >/dev/null || fail "$1 should be kept"
	QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$RF/$1" 2>/dev/null || fail "repush $1"
}

# on_origin BRANCH: succeed when BRANCH exists on origin.
on_origin() { [ -n "$(git ls-remote --heads origin "refs/heads/$1")" ]; }

V=9.0.0 OT="$V/500"
RF="$OT/RF1"
case_sandbox squash
git np "$V" >/dev/null && git np 500 >/dev/null && git np RF1 >/dev/null || fail "tree $RF"

# --- fixture: a, c integrated (kept); b pending; TESTING over b; both RELEASE; unmerged/old
integrate_keep a a.py
integrate_keep c c.py
git checkout -q "$RF/ORIGINAL" && git nr b >/dev/null || fail "nr b"
add_commit b.py "B = 1" "feat: add b"
git push -q origin "$RF/b" 2>/dev/null || fail "push b"
git checkout -q "$RF/ORIGINAL"
git testing crear "$RF/b" >/dev/null 2>&1 || fail "testing crear"
git branch "$OT/RELEASE" "$OT/ORIGINAL" && git branch "$V/RELEASE" "$V/ORIGINAL" || fail "release branches"
git branch unmerged/old develop
git checkout -q "$RF/ORIGINAL"
SHA="$(git log -n1 --format=%h --grep="Refs: $RF/a -> " "$RF/ORIGINAL")"

# --- A1 squash flow: integrated, pending, TESTING, RELEASE, unmerged
OUT="$(git arbol "$V" 2>&1)" || fail "A1 arbol failed: $OUT"
grep -q -- "- $RF/a .*= integrated as $SHA" <<<"$OUT" && ok "A1 integrated branch shows its squash commit" ||
	fail "A1 integrated: $OUT"
grep -q -- "- $RF/c .*= integrated as" <<<"$OUT" && ok "A1 second integrated branch" || fail "A1 c: $OUT"
grep -q -- "- $RF/b .*(+1 pending" <<<"$OUT" && ! grep -q -- "$RF/b .*integrated" <<<"$OUT" &&
	ok "A1 pending branch stays pending" || fail "A1 pending: $OUT"
! grep -q -- "$RF/a .*behind" <<<"$OUT" && ok "A1 integrated branch is not behind" || fail "A1 behind: $OUT"
grep -q -- "$RF/TESTING .*\[TESTING: sources $RF/b\]" <<<"$OUT" && ok "A1 TESTING with its sources" ||
	fail "A1 testing: $OUT"
grep -q -- "$OT/RELEASE .*\[OT RELEASE\]" <<<"$OUT" && ok "A1 OT RELEASE" || fail "A1 OT release: $OUT"
grep -q -- "$V/RELEASE .*\[version RELEASE\]" <<<"$OUT" && ok "A1 version RELEASE" || fail "A1 version release: $OUT"
OUT="$(git arbol unmerged 2>&1)" || fail "A1 arbol unmerged failed"
grep -q "~  unmerged/old" <<<"$OUT" && ok "A1 unmerged shown" || fail "A1 unmerged: $OUT"

# --- A2 --limpiar: a goes (local and origin); c stays (worktree), b, ORIGINAL, TESTING, RELEASE stay
git worktree add -q "$CASE_REPO.wt" "$RF/c" || fail "A2 worktree"
OUT="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "A2 limpiar failed: $OUT"
! git rev-parse -q --verify "refs/heads/$RF/a" >/dev/null && ! on_origin "$RF/a" &&
	ok "A2 integrated branch deleted locally and on origin" || fail "A2 a still there: $OUT"
git rev-parse -q --verify "refs/heads/$RF/c" >/dev/null && on_origin "$RF/c" &&
	grep -q "kept '$RF/c'.*worktree" <<<"$OUT" && ok "A2 branch checked out in a worktree kept" ||
	fail "A2 c: $OUT"
for k in "$RF/b" "$RF/ORIGINAL" "$RF/TESTING" "$OT/RELEASE" "$V/RELEASE" unmerged/old; do
	git rev-parse -q --verify "refs/heads/$k" >/dev/null || fail "A2 '$k' must stay"
done
ok "A2 pending, ORIGINAL, TESTING, RELEASE and unmerged kept"
OUT="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "A2 second limpiar failed"
grep -q "nothing to clean" <<<"$OUT" || grep -q "kept '$RF/c'" <<<"$OUT" && ok "A2 second run deletes nothing more" ||
	fail "A2 second run: $OUT"

# --- A3 flow = merge: the 4.x output, and --limpiar refused
case_sandbox merge
git np "$V" >/dev/null && git np 500 >/dev/null && git np RF1 >/dev/null || fail "merge tree"
git nr a >/dev/null || fail "merge nr a"
add_commit a.py "A = 1" "feat: add a"
git checkout -q "$RF/ORIGINAL"
OUT="$(git arbol "$V" 2>&1)" || fail "A3 arbol failed"
grep -q -- "- $RF/a .*(+1 pending)" <<<"$OUT" && ok "A3 merge flow prints the 4.x state" || fail "A3: $OUT"
! grep -q "integrated\|TESTING\|RELEASE" <<<"$OUT" && ok "A3 no squash annotations" || fail "A3 annotations: $OUT"
OUT="$(git arbol --limpiar --yes 2>&1)" && fail "A3 limpiar accepted with flow merge"
grep -q "branches.flow = squash" <<<"$OUT" && ok "A3 --limpiar needs flow squash" || fail "A3 limpiar message: $OUT"
