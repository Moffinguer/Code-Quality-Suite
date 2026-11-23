#!/usr/bin/env bash
# Case: the RC1 merge shape (7.1.1 merge_review, ACs MR1-MR2). Under flow = squash two integrations
# of 5.0.0-RC1/git/ORIGINAL became merge commits (11413d7: gatefix/bugfix -> gatefix/ORIGINAL,
# 375e139: gatefix/ORIGINAL -> git/ORIGINAL). This case rebuilds that shape in a sandbox and proves
# what each command does with it: every change must show once in the changelog, and both merged
# branches must count as integrated. A step that fails today is an expected failure (xfail): it is
# tied to a row of dev_documents/KNOWN-BUGS.md (local, git-ignored) by its date and "where" text,
# and the case fails when the step starts to pass, so the row gets closed.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

V=9.5.0 OT=git
GF="$V/$OT/gatefix"

# add_commit FILE TEXT SUBJECT: write TEXT into FILE, stage it and commit it with SUBJECT.
# Exits through fail when the commit is refused.
add_commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -q -m "$3" || fail "commit $3"
}

# lib CMD...: run CMD with the branch-model library loaded (policy of the sandbox).
lib() {
	# shellcheck source=scripts/git-flow-lib.sh
	(. "$SUITE/scripts/git-flow-lib.sh" && qs_policy_load && "$@")
}

# xfail_row DATE WHERE: look for the KNOWN-BUGS row of an expected failure. The log is local and
# git-ignored, so it is read from the suite checkout only when it exists (a CI run has no copy).
# Prints a warning on stderr when the log exists but has no row with that date and that text.
xfail_row() {
	local log="$SUITE/dev_documents/KNOWN-BUGS.md"
	[ -f "$log" ] || return 0
	grep -F "| $1 |" "$log" | grep -qF -- "$2" || echo "WARN: no KNOWN-BUGS.md row '$1 | $2'" >&2
}

# xfail DATE WHERE TEXT CMD...: TEXT describes a check that fails today because of a known bug
# (the KNOWN-BUGS row DATE + WHERE). CMD is the check. It is reported as an expected failure;
# when CMD passes the bug is fixed and the case fails, so the check becomes a normal one.
xfail() {
	local date="$1" where="$2" text="$3"
	shift 3
	xfail_row "$date" "$where"
	if "$@"; then
		fail "xfail: '$text' passes now; close the KNOWN-BUGS row '$date | $where' and make it a normal check"
	fi
	ok "xfail ($date $where): $text"
}

# merge_into BRANCH SIDE SUBJECT REFS: what a flow = merge integration did, made with plumbing (no
# hook runs): a two-parent commit on BRANCH whose tree is the merge of SIDE, with the Refs:,
# Commits: and Files: trailers of a squash message but no Squashed:. BRANCH is checked out.
merge_into() {
	local b="$1" side="$2" s="$3" refs="$4" tree m
	tree="$(git merge-tree --write-tree "$b" "$side")" || fail "merge-tree $side into $b"
	m="$(printf '%s\n\nRefs: %s\n\nCommits:\n%s\n\nFiles:\n%s\n' "$s" "$refs" \
		"$(git log --reverse --no-merges --format='- %h %s' "$b..$side")" \
		"$(git diff --name-status "$b" "$side")" |
		git commit-tree "$tree" -p "$b" -p "$side")" || fail "commit-tree $b"
	git update-ref "refs/heads/$b" "$m"
	git checkout -q "$b" && git reset -q --hard HEAD
}

# build_shape: a fresh squash sandbox with the RC1 shape, local and on origin. Sets bugtip, gftip
# and ottip (the tips of bugfix, gatefix/ORIGINAL and the OT ORIGINAL) and leaves develop checked
# out. Tree: V/git/gatefix/bugfix -> V/git/gatefix/ORIGINAL -> V/git/ORIGINAL -> V/ORIGINAL.
# Errors: exits 1 through fail when a step does not work.
build_shape() {
	case_sandbox squash
	git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "tree $V"
	git np "$OT" >/dev/null && add_commit own.py 'OWN = 1' "feat: own work of the OT" || fail "OT"
	git push -q origin "$V/$OT/ORIGINAL" 2>/dev/null || fail "push OT"
	git np gatefix >/dev/null && add_commit g1.py 'G1 = 1' "style: gatefix baseline" || fail "gatefix"
	git nr bugfix >/dev/null && add_commit b1.py 'B1 = 1' "fix: first bugfix change" &&
		add_commit b2.py 'B2 = 1' "fix: second bugfix change" || fail "bugfix"
	git push -q origin "$GF/bugfix" 2>/dev/null || fail "push bugfix"
	git checkout -q "$GF/ORIGINAL" && add_commit g2.py 'G2 = 1' "fix: gatefix change" || fail "gatefix 2"
	bugtip="$(git rev-parse "$GF/bugfix")"
	merge_into "$GF/ORIGINAL" "$GF/bugfix" "fix(gate): bugfix integrated by merge" "$GF/bugfix -> $GF/ORIGINAL"
	git push -q origin "$GF/ORIGINAL" 2>/dev/null || fail "push gatefix"
	gftip="$(git rev-parse "$GF/ORIGINAL")"
	merge_into "$V/$OT/ORIGINAL" "$GF/ORIGINAL" "fix(gate): gatefix integrated by merge" "$GF/ORIGINAL -> $V/$OT/ORIGINAL"
	git push -q origin "$V/$OT/ORIGINAL" 2>/dev/null || fail "push OT merge"
	ottip="$(git rev-parse "$V/$OT/ORIGINAL")"
	git checkout -q develop
}

# count_in TEXT PATTERN: print how many lines of TEXT contain the fixed string PATTERN.
count_in() { grep -cF -- "$2" <<<"$1" || true; }

# once TEXT PATTERN: succeed when exactly one line of TEXT contains the fixed string PATTERN.
once() { [ "$(count_in "$1" "$2")" = 1 ]; }

# preview_lists_all TEXT: succeed when the change list of a 'git changelog --ot' preview (the
# "- <hash> <subject>" lines before the CHANGELOG.md section) has as many lines as the section has
# "(<hash>; git)" lines.
preview_lists_all() {
	local list sect
	list="$(sed -n '/^From /,/^## CHANGELOG/p' <<<"$1" | grep -c '^- [0-9a-f]\{7\} ' || true)"
	sect="$(grep -c "; $OT)\$" <<<"$1" || true)"
	[ "$list" = "$sect" ]
}

# --- MR2: the shape and the trailers ------------------------------------------------------------
build_shape
[ "$(git rev-list --merges "$ottip" "^$V/ORIGINAL" | wc -l)" = 2 ] &&
	[ "$(git rev-list --count --no-merges "$ottip" "^$V/ORIGINAL")" = 5 ] &&
	[ "$(git log -1 --format=%p "$ottip" | wc -w)" = 2 ] && [ "$(git log -1 --format=%p "$gftip" | wc -w)" = 2 ] &&
	ok "shape: two merge commits (bugfix -> gatefix/ORIGINAL -> git/ORIGINAL) over five plain commits" ||
	fail "shape: $(git log --graph --oneline "$ottip" "^$V/ORIGINAL")"
body="$(git log -1 --format=%B "$ottip")"
grep -qxF "Refs: $GF/ORIGINAL -> $V/$OT/ORIGINAL" <<<"$body" && grep -q '^Commits:' <<<"$body" &&
	grep -q '^Files:' <<<"$body" && ! grep -q '^Squashed:' <<<"$body" &&
	ok "shape: the merge carries Refs:, Commits: and Files: but no Squashed: (as 375e139)" || fail "trailers: $body"
# MR1: the tree of each merge equals what a squash of the second parent on the first one gives
[ "$(git merge-tree --write-tree "$ottip^1" "$ottip^2")" = "$(git rev-parse "$ottip^{tree}")" ] &&
	[ "$(git merge-tree --write-tree "$gftip^1" "$gftip^2")" = "$(git rev-parse "$gftip^{tree}")" ] &&
	ok "MR1: each merge tree equals a squash replay on its first parent" || fail "squash replay differs"
[ "$(git diff --name-only "$ottip^1" "$ottip" | wc -l)" = "$(git log -1 --format=%B "$ottip" | sed -n '/^Files:/,$p' | grep -c '^[AMD]')" ] &&
	ok "MR1: the Files: block lists exactly the files the merge changes" || fail "Files: block"

# --- changelog: each change once ----------------------------------------------------------------
notes="$(python3 "$SUITE/engine/qs.py" release-notes --version "$V" --tip "$ottip" --base "$(git rev-parse "$V/ORIGINAL")" --ot "$OT")" ||
	fail "release-notes"
once "$notes" "- Own work of the OT (" && once "$notes" "- Bugfix integrated by merge (" &&
	once "$notes" "- Gatefix change (" && [ "$(count_in "$notes" '; git)')" = 3 ] &&
	ok "changelog: the merge integration and each plain change are listed once (a style: commit is no group)" ||
	fail "changelog: $notes"
out="$(git changelog --ot "$V/$OT" 2>&1)" || fail "git changelog --ot: $out"
once "$out" "- Own work of the OT (" && once "$out" "- Bugfix integrated by merge (" && once "$out" "- Gatefix change (" &&
	grep -qF "[ok] $GF/ORIGINAL: contained in $V/$OT/ORIGINAL" <<<"$out" &&
	grep -qF "[ok] $GF/bugfix: contained in $GF/ORIGINAL" <<<"$out" && ! grep -qF '[!!]' <<<"$out" &&
	ok "git changelog --ot: each change once; both merged branches are 'contained', none set aside" || fail "preview: $out"
xfail 2026-11-23 "OT release preview" "the preview change list shows the merged integrations like the section" \
	preview_lists_all "$out"

# --- integrated checks: by ancestry -------------------------------------------------------------
lib branch_integrated "$GF/bugfix" "$GF/ORIGINAL" && lib branch_integrated "$GF/ORIGINAL" "$V/$OT/ORIGINAL" &&
	[ -z "$(lib children_pending "$V/$OT/ORIGINAL")" ] && [ -z "$(lib children_pending "$GF/ORIGINAL")" ] &&
	ok "integrated: bugfix and gatefix/ORIGINAL count as integrated (ancestry), no pending child" || fail "integrated checks"
! lib integrated_sha "$GF/bugfix" "$GF/ORIGINAL" >/dev/null &&
	ok "integrated: a merge integration has no 'Squashed:' sha (ancestry is the only proof)" || fail "integrated_sha"

# --- git arbol --limpiar -----------------------------------------------------------------------
git checkout -q "$V/$OT/ORIGINAL"
out="$(git arbol --limpiar --yes "$V" 2>&1 </dev/null)" || fail "limpiar: $out"
gone=1
for b in "$GF/ORIGINAL" "$GF/bugfix"; do
	if git rev-parse -q --verify "refs/heads/$b" >/dev/null || [ -n "$(git ls-remote --heads origin "refs/heads/$b")" ]; then gone=0; fi
done
[ "$gone" = 1 ] && git merge-base --is-ancestor "$bugtip" "$ottip" && git rev-parse -q --verify "refs/heads/$V/$OT/ORIGINAL" >/dev/null &&
	ok "arbol --limpiar: one run deletes both merged branches (local and origin); the OT ORIGINAL stays" || fail "limpiar: $out"
out="$(git arbol --limpiar --yes "$V" 2>&1 </dev/null)" || fail "limpiar again: $out"
grep -q 'deleted' <<<"$out" && fail "limpiar again deleted: $out"
ok "arbol --limpiar: a second run deletes nothing"
git checkout -q develop

# --- OT release, version release ----------------------------------------------------------------
build_shape
git checkout -q "$V/$OT/ORIGINAL"
out="$(git release --ot "$V/$OT" --yes 2>&1)" || fail "release --ot: $out"
cl="$(git show "$V/$OT/RELEASE:CHANGELOG.md")"
once "$cl" "- Own work of the OT (" && once "$cl" "- Bugfix integrated by merge (" && once "$cl" "- Gatefix change (" &&
	grep -q ', 0 set aside' <<<"$out" && ok "release --ot: CHANGELOG lists each change once; nothing set aside" || fail "release --ot: $cl / $out"
git checkout -q develop
out="$(git release --version "$V" --yes 2>&1)" || fail "release --version: $out"
cl="$(git show "$V/RELEASE:CHANGELOG.md")"
once "$cl" "- Own work of the OT (" && once "$cl" "- Bugfix integrated by merge (" && once "$cl" "- Gatefix change (" &&
	[ -z "$(git rev-list --merges "develop..$V/RELEASE")" ] &&
	ok "release --version: one squash per OT, no merge commit, each change once" || fail "release --version: $cl"
out="$(git publicar --version "$V" --yes 2>&1)" || fail "publicar: $out"
[ "$(git log -1 --format=%p develop | wc -w)" = 1 ] && grep -q 'published' <<<"$out" &&
	ok "publicar: one commit on develop for the version; no merge commit reaches it" || fail "publicar: $out"
