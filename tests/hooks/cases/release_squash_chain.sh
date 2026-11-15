#!/usr/bin/env bash
# Release fixes of 5.0.0-RC1/git/relfix: (1) the version release brings each OT in as ONE squash
# commit, so an OT whose history holds merge commits (early flow = merge integrations) does not
# conflict, with two OTs in OT order; (2) a branch merged into a parent that was then squashed into
# the OT ORIGINAL (its tip is an ancestor of a recorded 'Squashed:' sha) is integrated: the OT
# release does not set it aside as unmerged/..., and git arbol --limpiar can delete it.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# add_commit FILE TEXT SUBJECT: write TEXT into FILE, stage it and commit it with SUBJECT.
add_commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -q -m "$3" || fail "commit $3"
}

# tree_with REV FILE TEXT: print the id of the tree of REV plus FILE holding TEXT (plumbing, no hooks).
tree_with() {
	local idx blob
	idx="$(mktemp -u "$T/idx-XXXX")"
	blob="$(printf '%s\n' "$3" | git hash-object -w --stdin)"
	GIT_INDEX_FILE="$idx" git read-tree "$1"
	GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$2"
	GIT_INDEX_FILE="$idx" git write-tree
	rm -f "$idx"
}

# ot_with_merge OT FILE TEXT SIDEFILE: on the version ORIGINAL of $V, create the OT ORIGINAL with one
# squash-integrated commit (FILE) and then, as an old flow = merge integration did, a merge commit
# of a side commit that adds SIDEFILE (plumbing); push it and run the OT release.
ot_with_merge() {
	local o="$1" f="$2" text="$3" side="$4" base sc tip mc
	git checkout -q "$V/ORIGINAL" && git np "$o" >/dev/null && git push -q origin "$V/$o/ORIGINAL" 2>/dev/null || fail "OT $o"
	base="$(git rev-parse HEAD)"
	git nr work >/dev/null || fail "nr work in $o"
	add_commit "$f" "$text" "feat: work of $o"
	git integra --yes -m "feat($o): add $f" >/dev/null 2>&1 || fail "integra in $o"
	tip="$(git rev-parse "$V/$o/ORIGINAL")"
	sc="$(git commit-tree "$(tree_with "$base" "$side" "side of $o")" -p "$base" -m "feat: side of $o")"
	mc="$(git commit-tree "$(tree_with "$tip" "$side" "side of $o")" -p "$tip" -p "$sc" -m "merge side of $o")"
	git update-ref "refs/heads/$V/$o/ORIGINAL" "$mc" "$tip"
	git checkout -q "$V/$o/ORIGINAL" && git reset -q --hard HEAD
	QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$V/$o/ORIGINAL" 2>/dev/null || fail "push $o"
	out="$(git release --yes 2>&1)" || fail "OT release $o: $out"
}

# --- R1: the version release over OTs whose history has merge commits, two OTs ----------------
V=9.8.0
case_sandbox squash
git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "tree $V"
ot_with_merge m m.py 'M = 1' m_side.txt
ot_with_merge n n.py 'N = 1' n_side.txt
[ -n "$(git rev-list --merges "$V/m/RELEASE")" ] || fail "R1 fixture: no merge commit in the OT history"
git checkout -q develop
out="$(git release --version "$V" --yes 2>&1)" || fail "R1: version release failed: $out"
subjects="$(git log --reverse --format=%s "develop..$V/RELEASE" | grep -v '^docs(readme)')"
expected="$(printf '%s\n' "chore(version): $V" "chore(ot): OT m of $V" "chore(ot): OT n of $V" "docs(changelog): $V")"
[ "$subjects" = "$expected" ] && [ -z "$(git rev-list --merges "develop..$V/RELEASE")" ] &&
	[ "$(git show "$V/RELEASE:m.py")" = 'M = 1' ] && [ "$(git show "$V/RELEASE:m_side.txt")" = 'side of m' ] &&
	[ "$(git show "$V/RELEASE:n.py")" = 'N = 1' ] && [ "$(git show "$V/RELEASE:n_side.txt")" = 'side of n' ] &&
	ok "R1: each OT is one squash commit in OT order, no merge commit, nothing replayed" || fail "R1: $subjects / $out"
body="$(git log -n1 --format=%B --grep="^chore(ot): OT m of $V" "$V/RELEASE")"
grep -qx "Squashed: $V/m/RELEASE [0-9a-f]\{40\}" <<<"$body" && grep -q "tag ot/$V/m" <<<"$body" && grep -q '^Files:' <<<"$body" &&
	ok "R1: the squash message names the OT, its tag and Squashed: <ot RELEASE> <sha>" || fail "R1 message: $body"
cl="$(git show "$V/RELEASE:CHANGELOG.md")"
[ "$(grep -c "^## \[\{0,1\}$V\]\{0,1\} - " <<<"$cl")" = 1 ] && [ "$(grep -c '^- ' <<<"$cl")" = 4 ] && grep -q '^- Add n.py (.*; n)$' <<<"$cl" &&
	[ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ "$(git for-each-ref --format='%(refname:short)' "refs/heads/$V/")" = "$V/RELEASE" ] &&
	ok "R1: the union CHANGELOG entry and the version tag are as before, the tree is deleted" || fail "R1 changelog: $cl"

# --- R2: a grandchild integrated by merge into a parent that was squashed ---------------------
V=9.9.0
case_sandbox squash
git np "$V" >/dev/null && git np 700 >/dev/null || fail "tree $V/700"
OT="$V/700"
git np pub >/dev/null && git np sub >/dev/null && git nr w >/dev/null || fail "tree pub/sub"
add_commit s.py 'S = 1' "feat: work in sub"
git integra --yes -m "feat(sub): add s" >/dev/null 2>&1 || fail "integra w into sub"
subtip="$(git rev-parse "$OT/pub/sub/ORIGINAL")"
pubtip="$(git rev-parse "$OT/pub/ORIGINAL")"
# the old way: sub/ORIGINAL merged (not squashed) into pub/ORIGINAL
mc="$(git commit-tree "$(git rev-parse "$subtip^{tree}")" -p "$pubtip" -p "$subtip" -m "merge sub into pub")"
git update-ref "refs/heads/$OT/pub/ORIGINAL" "$mc" "$pubtip"
git checkout -q "$OT/pub/ORIGINAL" && git reset -q --hard HEAD
git integra --yes -m "feat(pub): publish s" >/dev/null 2>&1 || fail "integra pub into the OT"
git checkout -q "$OT/ORIGINAL"
git log -n1 --format=%B | grep -q "^Squashed: $OT/pub/ORIGINAL " || fail "R2 fixture: pub was not squashed"
git rev-parse -q --verify "refs/heads/$OT/pub/sub/ORIGINAL" >/dev/null || fail "R2 fixture: sub is gone"
git checkout -q "$OT/ORIGINAL"
out="$(git arbol --limpiar </dev/null 2>&1 || true)"
grep -q "pub/sub/ORIGINAL" <<<"$out" && ! git branch --list "unmerged/*" | grep -q . &&
	ok "R2: arbol --limpiar sees the grandchild as integrated (in a branch squashed into the ORIGINAL)" || fail "R2 limpiar: $out / $(git arbol 2>&1) / $(git branch -a)"
git push -q origin "$OT/ORIGINAL" 2>/dev/null || true
out="$(git release --yes 2>&1)" || fail "R2: OT release failed: $out"
[ -z "$(git for-each-ref --format='%(refname:short)' 'refs/heads/unmerged*')" ] &&
	! git rev-parse -q --verify "refs/heads/$OT/pub/sub/ORIGINAL" >/dev/null &&
	ok "R2: the OT release deletes the grandchild, it is not set aside as unmerged/..." ||
	fail "R2: $(git branch -a) / $out"
