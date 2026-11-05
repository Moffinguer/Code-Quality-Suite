#!/usr/bin/env bash
# OT release with branches.flow = squash (5.0.0-RC1/git/publish/ot, ACs O1-O7): git release
# inside '<v>/<ot>/...' (or --ot) makes '<v>/<ot>/RELEASE' = OT ORIGINAL tip + one
# docs(changelog) commit with '(<hash>; <ot>)' lines, tags the OT ORIGINAL tip, pushes both,
# deletes the OT subtree (never-integrated branches set aside), resumes after a failed push, and
# never lets a TESTING sandbox block or enter the release.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# add_commit FILE TEXT SUBJECT: write TEXT into FILE, stage it and commit it with SUBJECT.
# Exits through fail when the commit is refused.
add_commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -q -m "$3" || fail "commit $3"
}

# state: print every ref with its object, the current branch and the work tree status (to prove
# that a refused or preview command changed nothing).
state() {
	git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags
	git branch --show-current
	git status --porcelain
}

# lib CMD...: run CMD with the branch-model library loaded (policy of the sandbox).
lib() {
	# shellcheck source=scripts/git-flow-lib.sh
	(. "$SUITE/scripts/git-flow-lib.sh" && qs_policy_load && "$@")
}

# testing_marker LEVEL BASE SOURCE: create LEVEL/TESTING at BASE plus an empty marker commit made
# with commit-tree (no hook runs), as 'git testing crear' records it: 'Sources:' with SOURCE and
# its sha, then the trailer 'Testing-Create: LEVEL/ORIGINAL <BASE sha>'. Prints nothing.
testing_marker() {
	local level="$1" base src="$3" m
	base="$(git rev-parse "$2")"
	m="$(printf 'chore(testing): create\n\nSources:\n%s %s\n\nTesting-Create: %s/ORIGINAL %s\n' \
		"$src" "$(git rev-parse "$src")" "$level" "$base" | git commit-tree "$base^{tree}" -p "$base")"
	git update-ref "refs/heads/$level/TESTING" "$m"
}

V=9.1.0 OT="$V/700"
case_sandbox squash
git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "tree $V"

# --- O5: reserved leaves, in any case, refused as ordinary segments ----------------------------
git np 700 >/dev/null || fail "np 700"
before="$(state)"
out="$(git nr release 2>&1)" && fail "git nr release accepted"
grep -q 'reserved' <<<"$out" || fail "nr release: $out"
out="$(git np Original 2>&1)" && fail "git np Original accepted"
grep -q 'reserved' <<<"$out" || fail "np Original: $out"
out="$(git nr Testing 2>&1)" && fail "git nr Testing accepted"
grep -q 'reserved' <<<"$out" || fail "nr Testing: $out"
out="$(printf '%s\n  700\n    Release\n' "$V" | git es -n 2>&1)" && fail "git es with a Release node accepted"
grep -q 'reserved' <<<"$out" || fail "es Release: $out"
out="$(printf '%s\n  700\n    RELEASE\n' "$V" | git es -n 2>&1)" && fail "git es with a RELEASE node accepted"
grep -q 'reserved' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "O5: git nr release / np Original / nr Testing / git es Release: refused, nothing changed" || fail "es RELEASE: $out"
lib valid_branch_name "$OT/RELEASE" >/dev/null && [ "$(lib parent_branch "$OT/RELEASE")" = "$V/ORIGINAL" ] &&
	! lib valid_branch_name "$OT/x/RELEASE" >/dev/null && ! lib valid_branch_name "$V/Original/x" >/dev/null &&
	ok "O5: <v>/<ot>/RELEASE is a valid name whose parent is <v>/ORIGINAL" || fail "O5: valid_branch_name"

# --- the OT: nested squash, siblings, a branch never integrated, two TESTING sandboxes ----------
git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push OT"
git np RF1 >/dev/null && git nr a >/dev/null && add_commit a.py 'A = 1' "feat: add a" || fail "RF1/a"
atip="$(git rev-parse HEAD)"
git integra --yes -m "feat(a): module a" >/dev/null 2>&1 || fail "integra a"
git integra --yes -m "feat(RF1): requirement one" >/dev/null 2>&1 || fail "integra RF1"
[ "$(git branch --show-current)" = "$OT/ORIGINAL" ] || fail "expected to be on $OT/ORIGINAL"
git branch -q "$OT/RF1/a" "$atip" # why: as if its deletion had been declined; RF1/ORIGINAL is gone
git nr b >/dev/null && add_commit b.py 'B = 1' "fix: repair b" || fail "b"
btip="$(git rev-parse HEAD)"
git integra --yes -m "fix(b): repair module b" >/dev/null 2>&1 || fail "integra b"
git branch -q "$OT/b" "$btip" # squash-integrated and kept: proved by Refs:/Squashed:
git nr c >/dev/null && add_commit c.py 'C = 1' "feat: add c" && git push -q origin "$OT/c" 2>/dev/null || fail "c"
git checkout -q "$OT/ORIGINAL" && git push -q origin "$OT/ORIGINAL" 2>/dev/null || fail "push OT ORIGINAL"
ottip="$(git rev-parse HEAD)"
testing_marker "$OT" "$ottip" "$OT/c"
testing_marker "$OT/RF2" "$ottip" "$OT/c"
tmp="$(git commit-tree -p "$OT/RF2/TESTING" -m "feat: tried on testing" \
	"$(printf '100644 blob %s\tt.py\n' "$(printf 'T = 1\n' | git hash-object -w --stdin)" | git mktree)")"
git update-ref "refs/heads/$OT/RF2/TESTING" "$tmp"

# --- O4: refusals; nothing changes, VERSION and README untouched -------------------------------
git checkout -q "$V/ORIGINAL" && git np 701 >/dev/null && git checkout -q "$V/ORIGINAL" || fail "np 701"
before="$(state)"
out="$(git release --ot "$V/701" --yes 2>&1)" && fail "O4: OT without own commits released"
grep -q 'no commit of its own' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "O4: an OT ORIGINAL without commits of its own is refused, nothing changed" || fail "O4 empty: $out"
git np 702 >/dev/null && add_commit e.py 'E = 1' "feat: add e" && git push -q origin "$V/702/ORIGINAL" 2>/dev/null &&
	git reset -q --hard HEAD~1 && add_commit e.py 'E = 2' "feat: add e again" || fail "702"
before="$(state)"
out="$(git release --yes 2>&1)" && fail "O4: diverged OT released"
grep -q 'diverged' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "O4: local and origin diverged: refused, nothing changed" || fail "O4 diverged: $out"
out="$(git release v9 --ot "$OT" --yes 2>&1)" && fail "O4: OT release with a tag accepted"
grep -q 'takes no tag' <<<"$out" || fail "O4 tag: $out"

# --- O1: git changelog inside the OT previews and changes nothing -----------------------------
git checkout -q "$OT/c"
before="$(state)"
out="$(git changelog 2>&1)" || fail "O1: preview failed: $out"
grep -q "^# OT release $OT" <<<"$out" && grep -q '; 700)$' <<<"$out" &&
	grep -q "\[!!\] $OT/c: 1 commit(s) not in $OT/ORIGINAL -> will be set aside as unmerged/$OT/c" <<<"$out" &&
	grep -q "\[ok\] $OT/RF1/a: contained in $OT/ORIGINAL" <<<"$out" && grep -q "\[ok\] $OT/b: contained" <<<"$out" &&
	grep -q "\[ok\] $OT/TESTING: contained" <<<"$out" && grep -q "$OT/RF2/TESTING: [0-9]* commit(s) not in" <<<"$out" &&
	grep -q 'feat: tried on testing' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "O1/O7: git changelog in the OT previews its release; changes nothing" || fail "O1 preview: $out"
git checkout -q develop
before="$(state)"
out2="$(git changelog --ot "$OT" 2>&1)" || fail "O1: --ot preview failed: $out2"
grep -q "^# OT release $OT" <<<"$out2" && [ "$(state)" = "$before" ] &&
	ok "O1: git changelog --ot <v>/<ot> from develop previews the same release" || fail "O1 --ot: $out2"

# --- O6: the push of RELEASE fails after its commit; running it again resumes ------------------
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile read o n r; do case "$r" in */RELEASE) exit 1 ;; esac; done; exit 0\n' \
	>"$CASE_REPO.git/hooks/pre-receive"
chmod +x "$CASE_REPO.git/hooks/pre-receive"
git checkout -q "$OT/ORIGINAL"
out="$(git release --yes 2>&1)" && fail "O6: release passed a refused push"
grep -q "push of $OT/RELEASE failed" <<<"$out" && [ "$(git rev-parse "$OT/RELEASE^")" = "$ottip" ] &&
	git rev-parse -q --verify "refs/heads/$OT/ORIGINAL" >/dev/null && git rev-parse -q --verify "refs/heads/$OT/c" >/dev/null &&
	[ -z "$(git ls-remote --heads origin "refs/heads/$OT/RELEASE")" ] &&
	ok "O6: a failed push leaves the OT tree untouched" || fail "O6 push failure: $out"
rm -f "$CASE_REPO.git/hooks/pre-receive"
out="$(git release --yes 2>&1)" || fail "O6: resume failed: $out"
grep -q 'resumed' <<<"$out" && [ "$(git rev-list --count "$ottip..$OT/RELEASE")" = 1 ] &&
	ok "O6: running git release again resumes (one changelog commit)" || fail "O6 resume: $out"

# --- O2: RELEASE = OT ORIGINAL tip + one docs(changelog) commit with the OT lines ---------------
cl="$(git show "$OT/RELEASE:CHANGELOG.md")"
n_changes="$(git log --first-parent --no-merges --format=%s "$ottip" "^$V/ORIGINAL" | grep -c '^\(feat\|fix\)')"
[ "$(git branch --show-current)" = "$OT/RELEASE" ] && [ "$(git log -1 --format=%s "$OT/RELEASE")" = "docs(changelog): $V 700" ] &&
	[ "$(git diff --name-only "$ottip" "$OT/RELEASE")" = CHANGELOG.md ] &&
	grep -q "^## $V - [0-9-]*$" <<<"$cl" && [ "$(grep -c '; 700)$' <<<"$cl")" = "$n_changes" ] &&
	ok "O2/O4: RELEASE = OT tip + docs(changelog) with one (hash; 700) line per change; VERSION and README untouched" ||
	fail "O2: $(git log --oneline "$V/ORIGINAL..$OT/RELEASE") / $cl"
for h in $(git log --first-parent --no-merges --format=%h "$ottip" "^$V/ORIGINAL"); do
	grep -q "($h; 700)" <<<"$cl" || fail "O2: hash $h missing from: $cl"
done
ok "O2: the hashes are the OT ORIGINAL first-parent commits"

# --- O3: tag, push, subtree deleted, never-integrated branches set aside -----------------------
[ "$(git cat-file -t "ot/$V/700")" = tag ] && [ "$(git rev-parse "ot/$V/700^{commit}")" = "$ottip" ] &&
	git ls-remote --tags origin | grep -q "refs/tags/ot/$V/700$" &&
	ok "O3: annotated tag ot/$V/700 on the OT ORIGINAL tip, pushed" || fail "O3 tag"
[ "$(git for-each-ref --format='%(refname:short)' "refs/heads/$OT/")" = "$OT/RELEASE" ] &&
	[ "$(git ls-remote --heads origin | awk '{print $2}' | grep "^refs/heads/$OT/")" = "refs/heads/$OT/RELEASE" ] &&
	git rev-parse -q --verify "refs/heads/unmerged/$OT/c" >/dev/null &&
	git ls-remote --heads origin | grep -q "refs/heads/unmerged/$OT/c$" &&
	! git rev-parse -q --verify "refs/heads/unmerged/$OT/b" >/dev/null &&
	! git rev-parse -q --verify "refs/heads/unmerged/$OT/RF1/a" >/dev/null &&
	ok "O3: OT subtree deleted; c set aside; squash-integrated a (nested) and b deleted" || fail "O3 tree: $(git branch -a)"

# --- O7: TESTING sandboxes ---------------------------------------------------------------------
! git rev-parse -q --verify "refs/heads/unmerged/$OT/TESTING" >/dev/null &&
	git rev-parse -q --verify "refs/heads/unmerged/$OT/RF2/TESTING" >/dev/null &&
	grep -q "$OT/RF2/TESTING has undistributed commits" <<<"$out" && grep -q 'feat: tried on testing' <<<"$out" &&
	! git ls-tree -r --name-only "$OT/RELEASE" | grep -qx t.py &&
	ok "O7: a clean TESTING is deleted; one with undistributed commits is set aside; neither enters RELEASE" ||
	fail "O7: $out"

# --- done: released; pre-push lets the frozen OT RELEASE go although the version ORIGINAL moved --
out="$(git release --yes 2>&1)" && grep -q 'already released' <<<"$out" ||
	fail "release again: $out"
git checkout -q "$V/ORIGINAL" && add_commit v.txt 'v' "chore: version note" &&
	git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "version ORIGINAL moved"
git checkout -q "$OT/RELEASE" && add_commit review.txt 'ok' "docs(changelog): review" || fail "review commit"
git push -q origin "$OT/RELEASE" 2>/dev/null &&
	ok "O5: pre-push accepts the OT RELEASE without the behind-parent check" || fail "push of the OT RELEASE refused"

# --- flow = merge keeps the 4.x git release: --ot refused --------------------------------------
case_sandbox merge
out="$(git release --ot "$V/700" --yes 2>&1)" && fail "--ot accepted with flow = merge"
grep -q 'merge flow' <<<"$out" && ok "flow = merge: --ot refused, 4.x release unchanged" || fail "merge flow: $out"
