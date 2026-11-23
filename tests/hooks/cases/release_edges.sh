#!/usr/bin/env bash
# QA of 5.0.0-RC1/git/relfix: edge cases of the OT squash in the version release (two OTs on the same
# file without and with a conflict, the stop steps and the rerun after the conflict is resolved),
# git combinar / git publicar over chore(ot) commits, squashed_in_chain with a patch-equal branch,
# and the climbing of git arbol --limpiar (it must keep diverged copies and unpushed squashes).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# sed_commit FILE LINE TEXT SUBJECT: replace line LINE of FILE with TEXT and commit it.
sed_commit() {
	local tmp
	tmp="$(mktemp "$T/sed-XXXX")"
	awk -v n="$2" -v t="$3" 'NR == n { print t; next } { print }' "$1" >"$tmp"
	cat "$tmp" >"$1"
	rm -f "$tmp"
	git add "$1"
	git commit -q -m "$4" || fail "commit $4"
}

# ot_edit VERSION OT LINE TEXT: on VERSION/ORIGINAL create the OT ORIGINAL with one integrated
# change of line LINE of f.txt, then run the OT release. Fails with the output when a step fails.
ot_edit() {
	local v="$1" o="$2" out
	git checkout -q "$v/ORIGINAL" && git np "$o" >/dev/null || fail "OT $o"
	git nr work >/dev/null || fail "nr work in $o"
	sed_commit f.txt "$3" "$4" "feat: edit line $3 in $o"
	git integra --yes -m "feat($o): edit f.txt" >/dev/null 2>&1 || fail "integra in $o"
	git push -q origin "$v/$o/ORIGINAL" 2>/dev/null || true
	out="$(git release --yes 2>&1)" || fail "OT release $o: $out"
}

# base_tree VERSION: develop gets a five line f.txt and the version tree VERSION is created.
base_tree() {
	git checkout -q develop
	printf 'l1\nl2\nl3\nl4\nl5\n' >f.txt
	git add f.txt
	git commit -q -m "chore: add f.txt" || fail "base f.txt"
	git push -q origin develop 2>/dev/null || fail "push base"
	git np "$1" >/dev/null && git push -q origin "$1/ORIGINAL" 2>/dev/null || fail "tree $1"
}

# --- E1: two OTs change different lines of the same file: no conflict -------------------------
V=9.1.0
case_sandbox squash
base_tree "$V"
ot_edit "$V" a 1 'A-line1'
ot_edit "$V" b 5 'B-line5'
git checkout -q develop
out="$(git release --version "$V" --yes 2>&1)" || fail "E1: version release: $out"
[ "$(git show "$V/RELEASE:f.txt" | tr '\n' ' ')" = 'A-line1 l2 l3 l4 B-line5 ' ] &&
	[ "$(git log --format=%s --grep='^chore(ot)' "develop..$V/RELEASE" | wc -l)" = 2 ] &&
	[ -z "$(git rev-list --merges "develop..$V/RELEASE")" ] &&
	ok "E1: two OTs on one file, different lines: both edits kept, one chore(ot) commit each" || fail "E1: $out"

# --- E2: the same line: conflict, stop steps, rerun after the resolution ---------------------
V=9.2.0
case_sandbox squash
base_tree "$V"
ot_edit "$V" c 3 'C-line3'
ot_edit "$V" d 3 'D-line3'
git checkout -q develop
rc=0
out="$(git release --version "$V" --yes 2>&1)" || rc=$?
[ "$rc" != 0 ] && grep -q "conflict while squashing OT d" <<<"$out" && grep -q 'git commit' <<<"$out" &&
	grep -q "git release --version $V" <<<"$out" && grep -q "git reset --hard $V/RELEASE" <<<"$out" &&
	grep -q '^<<<<<<<' f.txt && [ -z "$(git branch --show-current)" ] &&
	ok "E2: a conflicting OT stops with the steps (commit, rerun, reset), conflict markers in the tree" ||
	fail "E2 stop: rc=$rc $out"
# an unresolved rerun must refuse, not commit the markers
rc=0
out2="$(git release --version "$V" --yes 2>&1)" || rc=$?
[ "$rc" != 0 ] && ! git log -n1 --format=%B "$V/RELEASE" | grep -q '^chore(ot): OT d' &&
	ok "E2: a rerun with the conflict unresolved is refused, RELEASE untouched" || fail "E2 unresolved rerun: rc=$rc $out2"
printf 'l1\nl2\nC+D-line3\nl4\nl5\n' >f.txt
git add f.txt
git commit -q --no-edit || fail "E2: git commit of the resolution"
out="$(git release --version "$V" --yes 2>&1)" || fail "E2: rerun after the resolution: $out"
[ "$(git show "$V/RELEASE:f.txt" | sed -n 3p)" = 'C+D-line3' ] &&
	[ "$(git log --reverse --format=%s --grep='^chore(ot)' "develop..$V/RELEASE")" = "$(printf 'chore(ot): OT c of %s\nchore(ot): OT d of %s' "$V" "$V")" ] &&
	git log -n1 --format=%B --grep='^chore(ot): OT d' "$V/RELEASE" | grep -q "^Squashed: $V/d/RELEASE [0-9a-f]\{40\}$" &&
	[ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ "$(git show "$V/RELEASE:CHANGELOG.md" | grep -c "^## .*$V")" = 1 ] &&
	ok "E2: the rerun resumes: resolution kept, both OTs squashed in order, tag on the tip, one changelog entry" ||
	fail "E2 rerun: $out / $(git log --format=%s "develop..$V/RELEASE")"

# --- E3: git combinar and git publicar over chore(ot) commits --------------------------------
case_sandbox squash
released_ot() { # VERSION OT FILE TEXT: tree, OT with one file, OT release, version release
	git checkout -q develop
	git np "$1" >/dev/null && git push -q origin "$1/ORIGINAL" 2>/dev/null || fail "tree $1"
	git np "$2" >/dev/null && git nr work >/dev/null || fail "OT $1/$2"
	case_commit "$3" "$4" "feat: add $3"
	git integra --yes -m "feat($2): add $3" >/dev/null 2>&1 || fail "integra $1/$2"
	git push -q origin "$1/$2/ORIGINAL" 2>/dev/null || true
	git release --yes >/dev/null 2>&1 || fail "OT release $1/$2"
	git checkout -q develop
	git release --version "$1" --yes >/dev/null 2>&1 || fail "version release $1"
}
released_ot 9.3.0 301 p.txt 'P'
released_ot 9.3.1 302 q.txt 'Q'
git checkout -q develop
start="$(git rev-parse develop)"
out="$(git combinar --incluir 9.3.0,9.3.1 --version 9.3.2 --yes 2>&1)" || fail "E3: combinar: $out"
[ "$(git show 9.3.2/RELEASE:p.txt)" = P ] && [ "$(git show 9.3.2/RELEASE:q.txt)" = Q ] &&
	[ "$(git log --format=%s --grep='^chore(combine)' "develop..9.3.2/RELEASE" | wc -l)" = 2 ] &&
	git log --format=%B "develop..9.3.2/RELEASE" | grep -q 'chore(ot)' &&
	ok "E3: combinar keeps the work of the OT squashes of both RELEASEs (and their chore(ot) lines)" ||
	fail "E3 combinar: $out / $(git log --format=%s "develop..9.3.2/RELEASE")"
out="$(git publicar --version 9.3.2 --yes 2>&1)" || fail "E3: publicar: $out"
[ "$(git rev-list --count "$start..develop")" = 1 ] && [ "$(git rev-list --parents -n1 develop | wc -w)" = 2 ] &&
	[ "$(git show develop:p.txt)" = P ] && [ "$(git show develop:q.txt)" = Q ] &&
	ok "E3: publicar lands the combined release as ONE single-parent commit on develop" || fail "E3 publicar: $out"
# a plain version release with an OT, then publicar: one commit, the chore(ot) in its Commits:
case_sandbox squash
released_ot 9.4.0 401 r.txt 'R'
start="$(git rev-parse develop)"
out="$(git publicar --version 9.4.0 --yes 2>&1)" || fail "E3: publicar 9.4.0: $out"
[ "$(git rev-list --count "$start..develop")" = 1 ] && [ "$(git show develop:r.txt)" = R ] &&
	git log -n1 --format=%B develop | grep -q '^- [0-9a-f]* chore(ot): OT 401 of 9.4.0$' &&
	ok "E3: publicar of a version with an OT squash: ONE commit on develop, Commits: lists the chore(ot)" ||
	fail "E3 publicar 9.4.0: $(git log -n1 --format=%B develop)"

# --- E4: squashed_in_chain with a patch-equal branch that is not an ancestor ------------------
case_sandbox squash
# shellcheck source=scripts/git-flow-lib.sh
. "$SUITE/scripts/git-flow-lib.sh"
base="$(git rev-parse HEAD)"
git checkout -q -b origsrc "$base"
case_commit p.txt 'P' "feat: p"
src="$(git rev-parse HEAD)"
git checkout -q -b same "$base"
case_commit p.txt 'P' "feat: p again"
git checkout -q -b other "$base"
case_commit p.txt 'DIFFERENT' "feat: p other"
git checkout -q -b more "$base"
case_commit z.txt 'Z' "feat: z"
git checkout -q -b target "$base"
printf 'P\n' >p.txt
git add p.txt
git commit -q -m "feat: squash of origsrc" -m "Squashed: x/ORIGINAL $src" || fail "E4 squash commit"
! git merge-base --is-ancestor same target && ! git merge-base --is-ancestor same "$src" || fail "E4 fixture: same is an ancestor"
squashed_in_chain same target && ok "E4: a patch-equal branch (not an ancestor) is in the chain" || fail "E4 same"
squashed_in_chain origsrc target && ok "E4: the squashed tip itself is in the chain" || fail "E4 src"
! squashed_in_chain other target && ok "E4: a conflicting branch is not in the chain" || fail "E4 other"
! squashed_in_chain more target && ok "E4: a branch with extra work is not in the chain" || fail "E4 more"
! squashed_in_chain nonexistent target && ok "E4: a missing ref is not in the chain" || fail "E4 missing"

# --- E5: git arbol --limpiar climbs, and keeps what is not integrated -------------------------
V=9.5.0 OT="$V/500"
case_sandbox squash
git np "$V" >/dev/null && git np 500 >/dev/null || fail "tree $OT"
git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push OT"
git np pub >/dev/null || fail "pub"
for s in s1 s2 s3; do
	git checkout -q "$OT/pub/ORIGINAL" && git np "$s" >/dev/null && git nr w >/dev/null || fail "tree $s"
	case_commit "$s.py" "S = '$s'" "feat: work in $s"
	git integra --yes -m "feat($s): add $s" >/dev/null 2>&1 || fail "integra $s"
done
git checkout -q "$OT/pub/ORIGINAL"
for s in s1 s2 s3; do
	merged="$(git merge-tree --write-tree "$OT/pub/ORIGINAL" "$OT/pub/$s/ORIGINAL")" || fail "E5 merge-tree $s"
	mc="$(git commit-tree "$merged" -p "$OT/pub/ORIGINAL" -p "$OT/pub/$s/ORIGINAL" -m "merge $s into pub")"
	git update-ref "refs/heads/$OT/pub/ORIGINAL" "$mc"
	git reset -q --hard HEAD
done
for s in s1 s2 s3; do
	QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$OT/pub/$s/ORIGINAL" 2>/dev/null || fail "push $s"
done
git integra --yes -m "feat(pub): publish s1 s2 s3" >/dev/null 2>&1 || fail "integra pub"
git checkout -q "$OT/ORIGINAL"
! git rev-parse -q --verify "refs/heads/$OT/pub/ORIGINAL" >/dev/null || fail "E5 fixture: pub still exists"
# E5a: the squash is local only (origin/OT/ORIGINAL is behind): nothing may be deleted
out="$(git arbol --limpiar --yes "$V" 2>&1 </dev/null)" || true
[ -n "$(git for-each-ref "refs/heads/$OT/pub/s1/ORIGINAL" "refs/heads/$OT/pub/s2/ORIGINAL" "refs/heads/$OT/pub/s3/ORIGINAL")" ] &&
	[ "$(git ls-remote --heads origin "$OT/pub/*" | wc -l)" = 3 ] &&
	ok "E5a: unpushed squash: the grandchildren are kept (local and origin)" || fail "E5a: $out"
git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push OT squash"
# s2: extra local work; s3: local and origin diverged
git checkout -q "$OT/pub/s2/ORIGINAL"
case_commit s2_more.py 'M = 1' "feat: more in s2"
git checkout -q "$OT/ORIGINAL"
# s3: the local copy is rewritten (same tree, other parent: patch-equal, not an ancestor of origin's)
cp3="$(git rev-parse "$OT/pub/s3/ORIGINAL")"
git update-ref "refs/heads/$OT/pub/s3/ORIGINAL" "$(git commit-tree "$cp3^{tree}" -p "$cp3^" -m "feat: s3 rewritten")"
! git merge-base --is-ancestor "$OT/pub/s3/ORIGINAL" "origin/$OT/pub/s3/ORIGINAL" &&
	! git merge-base --is-ancestor "origin/$OT/pub/s3/ORIGINAL" "$OT/pub/s3/ORIGINAL" || fail "E5 fixture: s3 is not diverged"
out="$(git arbol --limpiar --yes "$V" 2>&1 </dev/null)" || fail "E5b: limpiar failed: $out"
! git rev-parse -q --verify "refs/heads/$OT/pub/s1/ORIGINAL" >/dev/null && [ -z "$(git ls-remote --heads origin "$OT/pub/s1/ORIGINAL")" ] &&
	ok "E5b: the grandchild merged into the squashed parent is deleted (climbed to the OT ORIGINAL)" || fail "E5b s1: $out"
git rev-parse -q --verify "refs/heads/$OT/pub/s2/ORIGINAL" >/dev/null && [ -n "$(git ls-remote --heads origin "$OT/pub/s2/ORIGINAL")" ] &&
	ok "E5b: a grandchild with unintegrated work is kept" || fail "E5b s2: $out"
git rev-parse -q --verify "refs/heads/$OT/pub/s3/ORIGINAL" >/dev/null && [ -n "$(git ls-remote --heads origin "$OT/pub/s3/ORIGINAL")" ] &&
	grep -q 'diverged' <<<"$out" && ok "E5b: diverged local and origin copies are kept, and said so" || fail "E5b s3: $out"
