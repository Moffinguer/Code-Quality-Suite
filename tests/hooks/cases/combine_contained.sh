#!/usr/bin/env bash
# QA of 6.0.0/special/combfix: git combinar when the later RELEASE already contains the earlier
# one (its content was merged in and squashed, so it is not an ancestor): no conflict and no second
# squash of the earlier one; the union changelog lists a commit hash once; and a real conflict
# between two RELEASEs is still refused.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# released VERSION OT FILE TEXT: tree VERSION with one OT adding FILE with TEXT; the OT release
# and the version release. Fails with the step name.
released() {
	git checkout -q develop
	git np "$1" >/dev/null && git push -q origin "$1/ORIGINAL" 2>/dev/null || fail "tree $1"
	released_ot "$2" "$3" "$4" "feat: add $3"
}

# released_ot OT FILE TEXT SUBJECT: on the checked out VERSION/ORIGINAL, an OT whose work branch
# sets FILE to TEXT, then the OT release and the version release (run from develop).
released_ot() {
	local v
	v="$(git rev-parse --abbrev-ref HEAD | cut -d/ -f1)"
	git np "$1" >/dev/null && git nr work >/dev/null || fail "OT $v/$1"
	printf '%s\n' "$3" >"$2"
	git add "$2"
	git commit -q -m "$4" || fail "commit $2"
	git integra --yes -m "feat($1): add $2" >/dev/null 2>&1 || fail "integra $v/$1"
	git push -q origin "$v/$1/ORIGINAL" 2>/dev/null || true
	git release --yes >/dev/null 2>&1 || fail "OT release $v/$1"
	git checkout -q develop
	git release --version "$v" --yes >/dev/null 2>&1 || fail "version release $v"
}

# --- C1: the later RELEASE already holds the earlier one (merged in, squashed, then went on) --
case_sandbox squash
released 9.7.0 701 p.txt 'P'
v0="$(git log -1 --format=%H --grep='^chore(version): 9.7.0' 9.7.0/RELEASE)"
ot0="$(git log -1 --format=%h --grep='^chore(ot)' 9.7.0/RELEASE)"
[ -n "$v0" ] && [ -n "$ot0" ] || fail "C1 fixture: no version or chore(ot) commit in 9.7.0/RELEASE"
# 9.7.1 grows from the version commit of 9.7.0 and takes its content in one sync commit that lists
# the commits it absorbs (what the real 6.0.0 did with 5.0.0-RC1)
git checkout -q develop
git branch 9.7.1/ORIGINAL "$v0"
GIT_INDEX_FILE="$T/c1.idx" git read-tree 9.7.1/ORIGINAL
GIT_INDEX_FILE="$T/c1.idx" git update-index --add --cacheinfo "100644,$(git rev-parse 9.7.0/RELEASE:p.txt),p.txt"
sync="$(git commit-tree "$(GIT_INDEX_FILE="$T/c1.idx" git write-tree)" -p 9.7.1/ORIGINAL -m "chore(sync): 9.7.0 into 9.7.1" -m "$(printf 'Commits:\n- %s chore(ot): OT 701 of 9.7.0' "$ot0")")"
git update-ref refs/heads/9.7.1/ORIGINAL "$sync"
git push -q origin 9.7.1/ORIGINAL 2>/dev/null || fail "C1 fixture: push 9.7.1/ORIGINAL"
git checkout -q 9.7.1/ORIGINAL
released_ot 702 p.txt 'P and more' "feat: extend p.txt"
git checkout -q develop
out="$(git combinar --incluir 9.7.0,9.7.1 --version 9.7.2 --yes 2>&1)" || fail "C1: combinar: $out"
[ "$(git show 9.7.2/RELEASE:p.txt)" = 'P and more' ] &&
	[ "$(git log --format=%s --grep='^chore(combine)' "develop..9.7.2/RELEASE" | wc -l)" = 1 ] &&
	grep -q 'already contained in 9.7.1/RELEASE' <<<"$out" &&
	ok "C1: a later RELEASE that already holds the earlier one: no conflict, one squash" ||
	fail "C1: $out / $(git log --format=%s "develop..9.7.2/RELEASE")"
# the union changelog lists each commit hash once
dups="$(git show 9.7.2/RELEASE:CHANGELOG.md | grep -o '([0-9a-f]\{7,\}[;)]' | sort | uniq -d)"
[ -z "$dups" ] &&
	ok "C1: the combined changelog lists no commit hash twice" || fail "C1: duplicated hashes: $dups"

# --- C2: two RELEASEs that really conflict are still refused ----------------------------------
case_sandbox squash
released 9.8.0 801 p.txt 'P1'
released 9.8.1 802 p.txt 'P2'
git checkout -q develop
rc=0
out="$(git combinar --incluir 9.8.0,9.8.1 --version 9.8.2 --yes 2>&1)" || rc=$?
[ "$rc" != 0 ] && grep -q 'conflict' <<<"$out" &&
	! git rev-parse -q --verify 9.8.2/RELEASE >/dev/null &&
	ok "C2: a real conflict between RELEASEs is still refused" || fail "C2: rc=$rc $out"
