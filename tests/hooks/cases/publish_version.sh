#!/usr/bin/env bash
# Version release with branches.flow = squash (5.0.0-RC1/git/publish/version, ACs V1-V6): git
# release --version <v> is refused while an OT lacks its '<v>/<ot>/RELEASE'; then '<v>/RELEASE' =
# '<v>/ORIGINAL' + every OT RELEASE squashed in as one commit (oldest first, CHANGELOG.md kept), the
# CHANGELOG.md entry = union of the reviewed OT sections, the annotated tag on its tip (local),
# the OT RELEASEs and '<v>/ORIGINAL' deleted; a conflict, a failed tag and a rejected push are all
# resumed by running git release again; flow = merge keeps the 4.x git release.
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
	git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags refs/remotes
	git branch --show-current
	git status --porcelain
	git config --get-regexp '^qs\.release\.' || true
}

# released_ot OT FILE TEXT SUBJECT DATE: on the version ORIGINAL of $V, create the OT ORIGINAL with
# one final branch that commits FILE (TEXT) and is squash-integrated with SUBJECT, both dated DATE
# (author and committer); push the OT ORIGINAL, run its OT release and leave its RELEASE checked
# out. Exits through fail on any error.
released_ot() {
	local o="$1" f="$2" text="$3" subject="$4" d="$5"
	git checkout -q "$V/ORIGINAL" && git np "$o" >/dev/null && git push -q origin "$V/$o/ORIGINAL" 2>/dev/null ||
		fail "OT $o"
	git nr work >/dev/null || fail "nr work in $o"
	GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" add_commit "$f" "$text" "feat: work of $o"
	GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git integra --yes -m "$subject" >/dev/null 2>&1 ||
		fail "integra in $o"
	git push -q origin "$V/$o/ORIGINAL" 2>/dev/null || fail "push $o"
	git release --yes >/dev/null 2>&1 || fail "OT release $o"
	[ "$(git branch --show-current)" = "$V/$o/RELEASE" ] || fail "OT release $o: not on its RELEASE"
}

# version_sandbox: a fresh squash sandbox with the version tree $V pushed.
version_sandbox() {
	case_sandbox squash
	git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "tree $V"
}

V=9.2.0
version_sandbox

# --- V1: OT b released, OT a not: refused, names a, nothing changed ----------------------------
released_ot b b.py 'B = 1' "fix(b): repair module b" "2020-01-01T10:00:00"
git checkout -q "$V/ORIGINAL" && git np a >/dev/null && git nr work >/dev/null &&
	GIT_AUTHOR_DATE=2021-01-01T10:00:00 add_commit a.py 'A = 1' "feat: work of a" &&
	GIT_AUTHOR_DATE=2021-01-01T10:00:00 git integra --yes -m "feat(a): add module a" >/dev/null 2>&1 &&
	git push -q origin "$V/a/ORIGINAL" 2>/dev/null || fail "OT a"
git checkout -q develop
before="$(state)"
out="$(git release --version "$V" --yes 2>&1)" && fail "V1: released while OT a has no RELEASE"
grep -q "OT a: no $V/a/RELEASE" <<<"$out" && ! grep -q "OT b" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "V1: git release --version refuses while OT a lacks its RELEASE, names it, changes nothing" ||
	fail "V1: $out"
out="$(git changelog --version "$V" 2>&1)" && fail "V1: preview says releasable"
grep -q "OT a: no $V/a/RELEASE" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "V1: git changelog --version shows the same refusal, changes nothing" || fail "V1 preview: $out"

# --- OT a released; a manual edit reviewed on its RELEASE --------------------------------------
git checkout -q "$V/a/ORIGINAL" && git release --yes >/dev/null 2>&1 || fail "OT release a"
ahash="$(git log -1 --format=%h "ot/$V/a")"
bhash="$(git log -1 --format=%h "ot/$V/b")"
grep -q "^- Add module a ($ahash; a)$" CHANGELOG.md || fail "OT a section: $(cat CHANGELOG.md)"
sed -i "s/^- Add module a ($ahash; a)$/- Add module a, reviewed by hand ($ahash; a)/" CHANGELOG.md
git add CHANGELOG.md && git commit -q -m "docs(changelog): review a" && git push -q origin "$V/a/RELEASE" 2>/dev/null ||
	fail "review commit on $V/a/RELEASE"
git checkout -q develop
before="$(state)"
out="$(git changelog --version "$V" 2>&1)" || fail "preview of the release: $out"
grep -q 'reviewed by hand' <<<"$out" && grep -q "($bhash; b)" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "V3: git changelog --version previews the union entry, changes nothing" || fail "preview: $out"

# --- V2: the release; b (older work) before a ------------------------------------------------
out="$(git release --version "$V" --yes 2>&1)" || fail "V2: version release failed: $out"
subjects="$(git log --reverse --format=%s "develop..$V/RELEASE")"
expected="$(printf '%s\n' "chore(version): $V" "chore(ot): OT b of $V" "chore(ot): OT a of $V" "docs(changelog): $V")"
[ "$(git branch --show-current)" = "$V/RELEASE" ] && [ "$(grep -v '^docs(readme)' <<<"$subjects")" = "$expected" ] &&
	ok "V2: $V/RELEASE = $V/ORIGINAL + one squash per OT, b then a (oldest first), then the release commits" ||
	fail "V2: $subjects"
[ "$(git show "$V/RELEASE:b.py")" = 'B = 1' ] && [ "$(git show "$V/RELEASE:a.py")" = 'A = 1' ] ||
	fail "V2: content of the OTs missing"

# --- V3: the union entry: both OTs, the reviewed text, each change once ------------------------
cl="$(git show "$V/RELEASE:CHANGELOG.md")"
[ "$(grep -c "^## \[\{0,1\}$V\]\{0,1\} - " <<<"$cl")" = 1 ] &&
	[ "$(grep -c "^- Add module a, reviewed by hand ($ahash; a)$" <<<"$cl")" = 1 ] &&
	[ "$(grep -c "^- Repair module b ($bhash; b)$" <<<"$cl")" = 1 ] &&
	! grep -q "^- Add module a ($ahash; a)$" <<<"$cl" && [ "$(grep -c '^- ' <<<"$cl")" = 2 ] &&
	ok "V3: the $V entry holds each OT change once, with its OT, keeping the manual edit" || fail "V3: $cl"

# --- V4: annotated tag on the RELEASE tip, local only, message = the entry ---------------------
[ "$(git cat-file -t "$V")" = tag ] && [ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ -z "$(git ls-remote --tags origin "refs/tags/$V")" ] &&
	git tag -l --format='%(contents)' "$V" | grep -q 'reviewed by hand' &&
	git tag -l --format='%(contents)' "$V" | grep -q '^### Fixed' &&
	ok "V4: annotated tag $V on the $V/RELEASE tip, local only, message = the entry" ||
	fail "V4: $(git tag -l --format='%(contents)' "$V")"

# --- V6: OT RELEASEs and the version ORIGINAL gone, ot/ tags kept ------------------------------
[ "$(git for-each-ref --format='%(refname:short)' "refs/heads/$V/")" = "$V/RELEASE" ] &&
	[ "$(git ls-remote --heads origin | awk '{print $2}' | grep "^refs/heads/$V/")" = "refs/heads/$V/RELEASE" ] &&
	git rev-parse -q --verify "refs/tags/ot/$V/a" >/dev/null && git rev-parse -q --verify "refs/tags/ot/$V/b" >/dev/null &&
	[ -z "$(git config --get-regexp "^qs\.release\.$V\.(plan|ots|current)")" ] &&
	ok "V6: OT RELEASEs and $V/ORIGINAL deleted (local, origin); ot/ tags kept; progress forgotten" ||
	fail "V6: $(git branch -a)"
out="$(git release --version "$V" --yes 2>&1)" && grep -q 'already prepared' <<<"$out" || fail "release again: $out"

# --- V5: a conflict between OTs stops; after git commit it resumes with the next OT --
V=9.3.0
version_sandbox
released_ot p shared.txt 'from p' "feat(p): shared text p" "2020-01-01T10:00:00"
released_ot q shared.txt 'from q' "feat(q): shared text q" "2020-02-01T10:00:00"
released_ot r r.txt 'from r' "feat(r): text r" "2020-03-01T10:00:00"
git checkout -q develop
out="$(git release --version "$V" --yes 2>&1)" && fail "V5: conflict not reported"
grep -q "conflict while squashing OT q" <<<"$out" && grep -q 'git commit' <<<"$out" &&
	[ "$(git log -1 --format=%s "$V/RELEASE")" = "chore(ot): OT p of $V" ] &&
	git rev-parse -q --verify "refs/heads/$V/ORIGINAL" >/dev/null &&
	[ "$(git rev-parse "$V/q/RELEASE")" = "$(git rev-parse "origin/$V/q/RELEASE")" ] &&
	ok "V5: the conflict stops with instructions; p is on RELEASE, the OT RELEASEs untouched" || fail "V5 stop: $out"
out="$(git release --version "$V" --yes 2>&1)" && fail "V5: ran with the conflict unsolved"
grep -q 'still has conflicts' <<<"$out" || fail "V5 unsolved conflict: $out"
printf 'from p\nfrom q\n' >shared.txt
git add shared.txt
git commit -q --no-edit || fail "commit of the solved squash"

# a rejected push after the resume: nothing changes on origin, the rerun completes
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile read o n r; do case "$r" in */RELEASE) exit 1 ;; esac; done; exit 0\n' \
	>"$CASE_REPO.git/hooks/pre-receive"
chmod +x "$CASE_REPO.git/hooks/pre-receive"
remote_before="$(git ls-remote origin)"
out="$(git release --version "$V" --yes 2>&1)" && fail "V5: release passed a rejected push"
grep -q 'OT q: the squash finished by hand' <<<"$out" && grep -q 'was rejected; nothing changed on origin' <<<"$out" &&
	[ "$(git ls-remote origin)" = "$remote_before" ] && git rev-parse -q --verify "refs/heads/$V/ORIGINAL" >/dev/null &&
	ok "V5: resumed after git commit; a rejected push leaves origin untouched" || fail "V5 push: $out"
rm -f "$CASE_REPO.git/hooks/pre-receive"
out="$(git release --version "$V" --yes 2>&1)" || fail "V5: resume after the push: $out"
subjects="$(git log --reverse --format=%s "develop..$V/RELEASE" | grep -v '^docs(readme)')"
[ "$subjects" = "$(printf '%s\n' "chore(version): $V" "chore(ot): OT p of $V" "chore(ot): OT q of $V" "chore(ot): OT r of $V" "docs(changelog): $V")" ] &&
	[ "$(git show "$V/RELEASE:shared.txt")" = "$(printf 'from p\nfrom q')" ] && [ "$(git show "$V/RELEASE:r.txt")" = 'from r' ] &&
	[ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ "$(git ls-remote origin "refs/heads/$V/RELEASE" | cut -f1)" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ "$(git for-each-ref --format='%(refname:short)' "refs/heads/$V/")" = "$V/RELEASE" ] &&
	[ "$(git show "$V/RELEASE:CHANGELOG.md" | grep -c '; [pqr])$')" = 3 ] &&
	ok "V5: the rerun goes on with r, tags, pushes once and deletes the tree" || fail "V5 resume: $subjects / $out"

# --- resume after a failed tag creation ---------------------------------------------------------
V=9.4.0
version_sandbox
released_ot x x.txt 'from x' "feat(x): text x" "2020-01-01T10:00:00"
git checkout -q develop
git update-ref "refs/tags/$V/block" HEAD # why: a ref folder where the tag must go
out="$(git release --version "$V" --yes 2>&1)" && fail "release passed a failed tag"
git update-ref -d "refs/tags/$V/block"
grep -q "the tag $V could not be created" <<<"$out" && git rev-parse -q --verify "refs/heads/$V/x/RELEASE" >/dev/null &&
	[ -z "$(git ls-remote --heads origin "refs/heads/$V/RELEASE")" ] || fail "tag failure state: $out"
out="$(git release --version "$V" --yes 2>&1)" || fail "resume after the tag failure: $out"
[ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	[ "$(git log --format=%s "develop..$V/RELEASE" | grep -c "^docs(changelog): $V$")" = 1 ] &&
	! git rev-parse -q --verify "refs/heads/$V/ORIGINAL" >/dev/null &&
	ok "a failed tag creation is resumed: one changelog commit, tag on the tip, tree deleted" || fail "tag resume: $out"

# --- flow = merge keeps the 4.x git release: no rebase of OTs, no tag at release time -----------
case_sandbox merge
V=9.5.0
git np "$V" >/dev/null && git np 900 >/dev/null && git nr work >/dev/null && add_commit w.py 'W = 1' "feat: work" &&
	git integra --yes -m "feat(w): add w" >/dev/null 2>&1 || fail "merge tree"
git checkout -q "$V/900/ORIGINAL" && git integra --yes -m "feat(900): ot 900" >/dev/null 2>&1 || fail "integra OT 900"
git push -q origin "$V/ORIGINAL" 2>/dev/null || true
git checkout -q develop
out="$(git release --version "$V" --yes 2>&1)" || fail "flow = merge: 4.x release failed: $out"
grep -q "$V prepared on $V/RELEASE" <<<"$out" && ! grep -q 'Version release' <<<"$out" &&
	! git rev-parse -q --verify "refs/tags/$V" >/dev/null &&
	[ -n "$(git rev-list --merges "develop..$V/RELEASE")" ] &&
	git log --format=%s "develop..$V/RELEASE" | grep -q "^docs(changelog): $V$" &&
	ok "flow = merge: git release keeps the 4.x one-level release (no OT check, no tag)" || fail "merge flow: $out"

# --- an abandoned release: stopped after the rebases (the tag cannot go), its RELEASE deleted by
# hand, an OT added; the rerun includes every OT and ignores the stale plan and ots -------------
V=9.6.0
version_sandbox
released_ot p p.txt 'from p' "feat(p): text p" "2020-01-01T10:00:00"
released_ot q q.txt 'from q' "feat(q): text q" "2020-02-01T10:00:00"
released_ot r r.txt 'from r' "feat(r): text r" "2020-03-01T10:00:00"
git checkout -q develop
git update-ref "refs/tags/$V/block" HEAD # why: a ref folder where the tag must go
out="$(git release --version "$V" --yes 2>&1)" && fail "abandon: the release passed a failed tag"
git update-ref -d "refs/tags/$V/block"
grep -q "the tag $V could not be created" <<<"$out" && [ "$(git config --get "qs.release.$V.plan")" = "p q r" ] ||
	fail "abandon: state after the stop: $out"
git checkout -q develop && git branch -q -D "$V/RELEASE" || fail "abandon: delete $V/RELEASE"
released_ot s s.txt 'from s' "feat(s): text s" "2020-04-01T10:00:00"
git checkout -q develop
before="$(state)"
out="$(git changelog --version "$V" 2>&1)" || fail "abandon: preview: $out"
[ "$(grep -c '^- OT ' <<<"$out")" = 4 ] && grep -q "^- OT s: $V/s/RELEASE$" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "abandon: the preview lists p, q, r and s, ignores the stale plan, changes nothing" || fail "abandon preview: $out"
out="$(git release --version "$V" --yes 2>&1)" || fail "abandon: rerun failed: $out"
grep -q "stale release state of $V is cleared" <<<"$out" || fail "abandon: no note: $out"
subjects="$(git log --reverse --format=%s "develop..$V/RELEASE" | grep -v '^docs(readme)')"
[ "$subjects" = "$(printf '%s\n' "chore(version): $V" "chore(ot): OT p of $V" "chore(ot): OT q of $V" \
	"chore(ot): OT r of $V" "chore(ot): OT s of $V" "docs(changelog): $V")" ] &&
	[ "$(git show "$V/RELEASE:s.txt")" = 'from s' ] && [ "$(git show "$V/RELEASE:p.txt")" = 'from p' ] &&
	[ -z "$(git config --get-regexp "^qs\.release\.$V\.(plan|ots|current)")" ] &&
	[ "$(git config --get "qs.release.$V.tag")" = "$V" ] &&
	[ "$(git for-each-ref --format='%(refname:short)' "refs/heads/$V/")" = "$V/RELEASE" ] &&
	[ "$(git rev-parse "$V^{commit}")" = "$(git rev-parse "$V/RELEASE")" ] &&
	ok "abandon: the rerun releases p, q, r and s, keeps the tag name for publicar, forgets the progress" ||
	fail "abandon rerun: $subjects / $out"

# --- git release --reset --version <v>: refused while <v>/RELEASE exists, then forgets the state -
V=9.7.0
version_sandbox
released_ot p p.txt 'from p' "feat(p): text p" "2020-01-01T10:00:00"
released_ot q q.txt 'from q' "feat(q): text q" "2020-02-01T10:00:00"
git checkout -q develop
git update-ref "refs/tags/$V/block" HEAD # why: as above, the release stops after the rebases
git release --version "$V" --yes >/dev/null 2>&1 && fail "reset: the release passed a failed tag"
git update-ref -d "refs/tags/$V/block"
before="$(state)"
out="$(git release --reset --version "$V" --yes 2>&1)" && fail "reset: ran while $V/RELEASE exists"
grep -q "exists: the release is in progress or prepared" <<<"$out" && [ "$(state)" = "$before" ] ||
	fail "reset refused while $V/RELEASE exists: $out"
git checkout -q develop && git branch -q -D "$V/RELEASE" || fail "reset: delete $V/RELEASE"
out="$(git release --reset --version "$V" --yes 2>&1)" || fail "reset: $out"
grep -q "release state of $V forgotten" <<<"$out" && [ -z "$(git config --get-regexp "^qs\.release\.$V\.")" ] &&
	ok "reset: refused while $V/RELEASE exists; with --yes it forgets plan, ots and tag, changes no branch" ||
	fail "reset: $out / $(git config --get-regexp "^qs\.release\.")"
out="$(git release --reset --version "$V" --yes 2>&1)" || fail "reset again: $out"
grep -q "nothing to reset" <<<"$out" && ok "reset: nothing to reset when no state is left" || fail "reset again: $out"
out="$(git release --version "$V" --yes 2>&1)" || fail "release after reset: $out"
[ "$(git log --reverse --format=%s "develop..$V/RELEASE" | grep -c '^chore(ot): OT')" = 2 ] &&
	ok "reset: the next release takes every OT of the version" || fail "release after reset: $out"
