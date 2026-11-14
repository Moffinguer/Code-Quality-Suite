#!/usr/bin/env bash
# git publicar / git combinar with branches.flow = squash (5.0.0-RC1/git/publish/mainline, ACs
# M1-M6): '<v>/RELEASE' is rebased onto develop (release-file conflicts solved, any other conflict
# stops and a re-run resumes) and lands as ONE single-parent commit; the tag is moved onto that
# commit and pushed with develop atomically; RELEASE is deleted. Several versions published in
# turn give one commit each; git combinar of two RELEASEs gives one commit; flow = merge keeps
# the 4.x git publicar.
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

# refs_state: print every branch, tag and remote-tracking ref with its object, and the refs of
# origin (to prove that a stopped or refused command moved nothing).
refs_state() {
	git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags refs/remotes
	git ls-remote origin
}

# released_version V OT FILE TEXT SUBJECT DATE: from develop, the version tree V with one OT whose
# final branch commits FILE (TEXT), squash-integrated with SUBJECT (dated DATE); then the OT
# release and the version release, leaving '<V>/RELEASE' (local tag V on its tip) and develop
# checked out. Exits through fail on any error.
released_version() {
	local v="$1" o="$2" f="$3" text="$4" subject="$5" d="$6"
	git checkout -q develop
	git np "$v" >/dev/null && git push -q origin "$v/ORIGINAL" 2>/dev/null || fail "tree $v"
	git np "$o" >/dev/null && git push -q origin "$v/$o/ORIGINAL" 2>/dev/null || fail "OT $o of $v"
	git nr work >/dev/null || fail "nr work in $v/$o"
	GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" add_commit "$f" "$text" "feat: work of $o"
	GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git integra --yes -m "$subject" >/dev/null 2>&1 ||
		fail "integra in $v/$o"
	git push -q origin "$v/$o/ORIGINAL" 2>/dev/null || fail "push $v/$o"
	git release --yes >/dev/null 2>&1 || fail "OT release $v/$o"
	git release --version "$v" --yes >/dev/null 2>&1 || fail "version release $v"
	[ "$(git branch --show-current)" = "$v/RELEASE" ] || fail "version release $v: not on its RELEASE"
	git checkout -q develop
}

# landed_one V OLD: succeed when develop has exactly one commit since OLD, with one parent, the
# subject chore(release): V, the tree of the RELEASE tip it names ('Squashed:'), a body with
# the changelog entry, Commits:, Files: and 'Refs: V/RELEASE -> develop'; the tag V on that
# commit, locally and on origin; origin develop at it; V/RELEASE gone (local and origin).
landed_one() {
	local v="$1" old="$2" body sq dev
	dev="$(git rev-parse develop)"
	body="$(git log -1 --format=%B develop)"
	sq="$(sed -n "s#^Squashed: $v/RELEASE ##p" <<<"$body")"
	[ "$(git rev-list --count "$old..develop")" = 1 ] &&
		[ "$(git rev-list --parents -n1 develop | wc -w)" = 2 ] &&
		[ "$(git log -1 --format=%s develop)" = "chore(release): $v" ] &&
		[ -n "$sq" ] && [ "$(git rev-parse "$sq^{tree}")" = "$(git rev-parse "develop^{tree}")" ] &&
		grep -qx 'Commits:' <<<"$body" && grep -qx 'Files:' <<<"$body" &&
		grep -qxF "Refs: $v/RELEASE -> develop" <<<"$body" && grep -q '^### ' <<<"$body" &&
		[ "$(git rev-parse "$v^{commit}")" = "$dev" ] && [ "$(git cat-file -t "$v")" = tag ] &&
		[ "$(git ls-remote --tags origin "refs/tags/$v^{}" | cut -f1)" = "$dev" ] &&
		[ "$(git ls-remote --heads origin refs/heads/develop | cut -f1)" = "$dev" ] &&
		! git rev-parse -q --verify "refs/heads/$v/RELEASE" >/dev/null &&
		[ -z "$(git ls-remote --heads origin "refs/heads/$v/RELEASE")" ]
}

# --- sandbox 1: six versions prepared from the same develop -----------------------------------
case_sandbox squash
released_version 9.2.0 a a.txt 'from a' "feat(a): add module a" "2020-01-01T10:00:00"
released_version 9.3.0 b b.txt 'from b' "fix(b): repair module b" "2020-02-01T10:00:00"
released_version 9.4.0 c c.txt 'from c' "feat(c): add module c" "2020-03-01T10:00:00"
released_version 9.5.0 d shared.txt 'from d' "feat(d): add shared text" "2020-04-01T10:00:00"
released_version 9.6.0 e shared.txt 'from e' "feat(e): other shared text" "2020-05-01T10:00:00"
released_version 9.1.0 z z.txt 'from z' "feat(z): add module z" "2020-07-01T10:00:00"
start="$(git rev-parse develop)"

# --- M6: several RELEASEs, no --version: refused as in 4.x, nothing changed --------------------
before="$(refs_state)"
out="$(git publicar --yes 2>&1)" && fail "M6: publicar picked one of six RELEASEs"
grep -q 'publish one at a time: git publicar --version' <<<"$out" && [ "$(refs_state)" = "$before" ] &&
	ok "M6: several RELEASE branches and no --version: refused, nothing changed" || fail "M6: $out"

# --- hooks: a RELEASE is never merged into develop, nor rebased onto another RELEASE ----------
out="$(git merge --no-ff --no-edit 9.2.0/RELEASE 2>&1)" && fail "hook: RELEASE merged into develop"
git merge --abort 2>/dev/null || true
grep -q "use 'git publicar'" <<<"$out" && [ "$(git rev-parse develop)" = "$start" ] &&
	ok "pre-merge-commit: a RELEASE -> develop merge commit is refused (git publicar)" || fail "merge hook: $out"
out="$(git rebase 9.3.0/RELEASE 9.2.0/RELEASE 2>&1)" && fail "hook: RELEASE rebased onto another RELEASE"
git rebase --abort 2>/dev/null || true
git checkout -q develop
grep -q 'pre-rebase' <<<"$out" && [ "$(git rev-parse 9.2.0/RELEASE)" = "$(git rev-parse origin/9.2.0/RELEASE)" ] &&
	ok "pre-rebase: a RELEASE rebases only onto develop" || fail "rebase hook: $out"

# --- M2/M3: one version lands as ONE commit; the tag on it; RELEASE deleted -------------------
out="$(git publicar --version 9.2.0 --yes 2>&1)" || fail "publicar 9.2.0: $out"
landed_one 9.2.0 "$start" && git show develop:CHANGELOG.md | grep -q '^- Add module a (' &&
	[ "$(git show develop:VERSION)" = 9.2.0 ] && [ "$(git branch --show-current)" = develop ] &&
	ok "M2/M3: 9.2.0 lands as one single-parent commit (tree, Commits/Files/Refs); tag 9.2.0 on it, pushed; RELEASE deleted" ||
	fail "M2 9.2.0: $out / $(git log -1 --format=%B develop)"

# --- M1: develop moved: the rebase solves the release files; a second version, a second commit --
one="$(git rev-parse develop)"
out="$(git publicar --version 9.3.0 --yes 2>&1)" || fail "publicar 9.3.0: $out"
cl="$(git show develop:CHANGELOG.md)"
n3="$(grep -n '^## \[\{0,1\}9\.3\.0' <<<"$cl" | cut -d: -f1)"
n2="$(grep -n '^## \[\{0,1\}9\.2\.0' <<<"$cl" | cut -d: -f1)"
landed_one 9.3.0 "$one" && [ "$(git rev-list --count "$start..develop")" = 2 ] &&
	[ -z "$(git rev-list --merges "$start..develop")" ] &&
	[ -n "$n3" ] && [ -n "$n2" ] && [ "$n3" -lt "$n2" ] && [ "$(grep -c '^## ' <<<"$cl")" = 2 ] &&
	[ "$(git show develop:VERSION)" = 9.3.0 ] && [ "$(git show develop:a.txt)" = 'from a' ] &&
	[ "$(git show develop:b.txt)" = 'from b' ] && [ "$(git rev-parse "9.2.0^{commit}")" = "$(git rev-parse develop~1)" ] &&
	grep -q 'release files solved' <<<"$out" &&
	ok "M1: two versions published in turn give two commits; CHANGELOG keeps both entries (newest first), VERSION the RELEASE's" ||
	fail "M1 9.3.0: $out / $cl"

# --- M4: git subir on a RELEASE rebases onto develop and force-with-lease pushes --------------
git checkout -q 9.4.0/RELEASE
tip4="$(git rev-parse HEAD)"
# why: -X theirs makes the merge clean; pre-merge-commit only runs for a merge without conflicts
out="$(git merge --no-edit -X theirs develop 2>&1)" && fail "hook: develop merged into 9.4.0/RELEASE"
git merge --abort 2>/dev/null || true
grep -q "use 'git subir'" <<<"$out" && [ "$(git rev-parse HEAD)" = "$tip4" ] &&
	ok "pre-merge-commit: develop is never merged into a RELEASE (git subir rebases it)" || fail "merge into RELEASE: $out"
out="$(git subir 2>&1)" || fail "M4: git subir on 9.4.0/RELEASE: $out"
git merge-base --is-ancestor develop 9.4.0/RELEASE &&
	[ "$(git ls-remote --heads origin refs/heads/9.4.0/RELEASE | cut -f1)" = "$(git rev-parse 9.4.0/RELEASE)" ] &&
	[ "$(git show 9.4.0/RELEASE:VERSION)" = 9.4.0 ] &&
	ok "M4: git subir on 9.4.0/RELEASE rebases it onto develop (release files solved) and pushes it" || fail "M4: $out"
two="$(git rev-parse develop)"
out="$(git publicar --version 9.4.0 --yes 2>&1)" || fail "publicar 9.4.0: $out"
landed_one 9.4.0 "$two" && ok "M2: the RELEASE already on develop lands as one commit, no rebase" || fail "9.4.0: $out"

# --- M1: a conflict with develop stops, changes nothing visible, and the re-run resumes --------
# why: 9.5.0 (published first) and 9.6.0 both write shared.txt, so 9.6.0 conflicts with develop
three="$(git rev-parse develop)"
out="$(git publicar --version 9.5.0 --yes 2>&1)" || fail "publicar 9.5.0: $out"
landed_one 9.5.0 "$three" || fail "9.5.0: $out"
four="$(git rev-parse develop)"
before="$(refs_state)"
out="$(git publicar --version 9.6.0 --yes 2>&1)" && fail "M1: the conflict on shared.txt was not reported"
grep -q 'conflict while rebasing 9.6.0/RELEASE onto develop' <<<"$out" && grep -q 'shared.txt' <<<"$out" &&
	grep -q 'git rebase --continue' <<<"$out" && grep -q 'git publicar --version 9.6.0' <<<"$out" &&
	[ "$(refs_state)" = "$before" ] && [ -d "$(git rev-parse --git-path rebase-merge)" ] &&
	ok "M1: a conflict on shared.txt stops with the steps; no branch, tag or origin ref moved" || fail "M1 stop: $out"
out="$(git publicar --version 9.6.0 --yes 2>&1)" && fail "M1: re-run passed an unsolved conflict"
[ "$(refs_state)" = "$before" ] && grep -q 'conflict while rebasing' <<<"$out" &&
	ok "M1: re-run with the conflict unsolved repeats the steps, changes nothing" || fail "M1 rerun: $out"
printf 'from d\nfrom e\n' >shared.txt
git add shared.txt
GIT_EDITOR=true git rebase --continue >/dev/null 2>&1 || true
out="$(git publicar --version 9.6.0 --yes 2>&1)" || fail "M1: resume after git rebase --continue: $out"
landed_one 9.6.0 "$four" && [ "$(git show develop:shared.txt)" = "$(printf 'from d\nfrom e')" ] &&
	[ "$(git show develop:VERSION)" = 9.6.0 ] && [ "$(git show develop:CHANGELOG.md | grep -c '^## ')" = 5 ] &&
	[ -z "$(git config --get-regexp '^qs\.publish\.')" ] &&
	ok "M1: after git rebase --continue, git publicar resumes and lands 9.6.0 as one commit" || fail "M1 resume: $out"
[ "$(git rev-list --count "$start..develop")" = 5 ] && [ -z "$(git rev-list --merges "$start..develop")" ] &&
	ok "five versions published in turn: five single-parent commits on develop" || fail "five versions"

# --- a rejected push: nothing on origin changes; the re-run resumes after the commit ----------
released_version 9.7.0 f f.txt 'from f' "feat(f): add module f" "2020-06-01T10:00:00"
five="$(git rev-parse develop)"
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/develop ] && exit 1; done; exit 0\n' \
	>"$CASE_REPO.git/hooks/pre-receive"
chmod +x "$CASE_REPO.git/hooks/pre-receive"
remote_before="$(git ls-remote origin)"
out="$(git publicar --version 9.7.0 --yes 2>&1)" && fail "publicar passed a rejected push"
grep -q 'push failed' <<<"$out" && [ "$(git ls-remote origin)" = "$remote_before" ] &&
	git rev-parse -q --verify refs/heads/9.7.0/RELEASE >/dev/null &&
	[ "$(git rev-parse "9.7.0^{commit}")" = "$(git rev-parse develop)" ] &&
	ok "a rejected push changes nothing on origin; develop, the tag and RELEASE stay ready locally" ||
	fail "push failure: $out"
rm -f "$CASE_REPO.git/hooks/pre-receive"
out="$(git publicar --version 9.7.0 --yes 2>&1)" || fail "resume after the push: $out"
landed_one 9.7.0 "$five" && grep -q 'already on develop' <<<"$out" &&
	ok "the re-run after a rejected push pushes the same commit (no second one)" || fail "push resume: $out"

# --- a develop commit the hooks reject (9.1.0 after 9.7.0): RELEASE put back, nothing changed ---
git checkout -q 9.1.0/RELEASE
before="$(refs_state)"
out="$(git publicar --version 9.1.0 --yes 2>&1)" && fail "an older version reached develop after a newer one"
grep -q 'release files solved' <<<"$out" && grep -q 'the commit on develop failed' <<<"$out" &&
	[ "$(refs_state)" = "$before" ] && [ "$(git branch --show-current)" = 9.1.0/RELEASE ] &&
	[ -z "$(git status --porcelain)" ] && [ -z "$(git config --get-regexp '^qs\.publish\.')" ] &&
	ok "a rejected develop commit after the rebase puts RELEASE and develop back: nothing changed" ||
	fail "rejected commit: $out"

# --- sandbox 2: M5 git combinar of two RELEASEs, then ONE commit on develop -------------------
case_sandbox squash
released_version 8.1.0 g g.txt 'from g' "feat(g): add module g" "2020-01-01T10:00:00"
released_version 8.2.0 h h.txt 'from h' "fix(h): repair module h" "2020-02-01T10:00:00"
start="$(git rev-parse develop)"
out="$(git combinar --incluir 8.1.0,8.2.0 --version 8.3.0 --yes 2>&1)" || fail "M5: combinar: $out"
cl="$(git show 8.3.0/RELEASE:CHANGELOG.md)"
[ "$(grep -c '^## ' <<<"$cl")" = 1 ] && grep -q '^## \[\{0,1\}8\.3\.0' <<<"$cl" &&
	grep -q '^- Add module g (' <<<"$cl" && grep -q '^- Repair module h (' <<<"$cl" &&
	git rev-parse -q --verify refs/heads/unmerged/8.1.0/RELEASE >/dev/null &&
	git rev-parse -q --verify refs/heads/unmerged/8.2.0/RELEASE >/dev/null &&
	! git rev-parse -q --verify refs/tags/8.1.0 >/dev/null && ! git rev-parse -q --verify refs/tags/8.2.0 >/dev/null &&
	[ "$(git log --format=%B "develop..8.3.0/RELEASE" --grep='^chore(combine)' | grep -c '^Files:$')" = 2 ] &&
	ok "M5: combinar unites the 8.1.0 and 8.2.0 sections into 8.3.0 (sources removed), Files: in each squash, source tags dropped" ||
	fail "M5 combinar: $out / $cl"
out="$(git publicar --version 8.3.0 --yes 2>&1)" || fail "M5: publicar 8.3.0: $out"
body="$(git log -1 --format=%B develop)"
landed_one 8.3.0 "$start" && grep -q '^Squashes: 8\.1\.0/RELEASE [0-9a-f]\{40\}$' <<<"$body" &&
	grep -q '^Squashes: 8\.2\.0/RELEASE [0-9a-f]\{40\}$' <<<"$body" &&
	[ "$(git show develop:g.txt)" = 'from g' ] && [ "$(git show develop:h.txt)" = 'from h' ] &&
	ok "M5: the combined 8.3.0 lands as ONE commit listing Squashes: of both sources" || fail "M5 publicar: $out / $body"

# --- sandbox 3: flow = merge keeps the 4.x git publicar (merge commit, tag on RELEASE) --------
case_sandbox merge
V=7.9.0
git np "$V" >/dev/null && git np 900 >/dev/null && git nr work >/dev/null && add_commit w.py 'W = 1' "feat: work" &&
	git integra --yes -m "feat(w): add w" >/dev/null 2>&1 || fail "merge tree"
git checkout -q "$V/900/ORIGINAL" && git integra --yes -m "feat(900): ot 900" >/dev/null 2>&1 || fail "integra OT 900"
git push -q origin "$V/ORIGINAL" 2>/dev/null || true
git checkout -q develop
git release --version "$V" --yes >/dev/null 2>&1 || fail "flow = merge: release"
rel="$(git rev-parse "$V/RELEASE")"
out="$(git publicar --version "$V" --yes 2>&1)" || fail "flow = merge: publicar: $out"
[ "$(git rev-list --parents -n1 develop | wc -w)" = 3 ] && [ "$(git rev-parse develop^2)" = "$rel" ] &&
	[ "$(git log -1 --format=%s develop)" = "chore(release): $V" ] && [ "$(git rev-parse "$V^{commit}")" = "$rel" ] &&
	! git rev-parse -q --verify "refs/heads/$V/RELEASE" >/dev/null && ! grep -q 'Squashed:' <<<"$(git log -1 --format=%B develop)" &&
	ok "flow = merge: git publicar keeps the 4.x merge commit, tag on the RELEASE tip" || fail "merge flow publicar: $out"

# --- sandbox 4: only release-owned lines are solved; develop's edits next to them are kept -----
case_sandbox squash
POM='<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>t</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
  <name>app</name>
</project>'
plumb_commit both develop pom.xml "$POM" "build: add pom.xml" >/dev/null
released_version 6.1.0 p p.txt 'from p' "feat(p): add module p" "2020-01-01T10:00:00"
out="$(git publicar --version 6.1.0 --yes 2>&1)" || fail "publicar 6.1.0: $out"
git show develop:README.md | grep -q 'qs:version.*6\.1\.0' && git show develop:pom.xml | grep -q '<version>6\.1\.0</version>' ||
	fail "fixture: develop has no 6.1.0 badge or pom version: $(git show develop:README.md) $(git show develop:pom.xml)"
released_version 6.2.0 q q.txt 'from q' "feat(q): add module q" "2020-02-01T10:00:00"
# why: develop edits the line right after the badge and the line right after the project version,
# so a plain merge puts each edit in the same conflict hunk as the RELEASE's badge / version
plumb_commit both develop README.md "$(git show develop:README.md | sed '/qs:version/a Develop note.')" \
	"docs: develop note under the badge" >/dev/null
plumb_commit both develop pom.xml "$(git show develop:pom.xml | sed 's#<name>app</name>#<name>app (develop)</name>#')" \
	"build: rename the app on develop" >/dev/null
old="$(git rev-parse develop)"
out="$(git publicar --version 6.2.0 --yes 2>&1)" || fail "publicar 6.2.0 with develop edits next to the release lines: $out"
readme="$(git show develop:README.md)"
pom="$(git show develop:pom.xml)"
landed_one 6.2.0 "$old" && grep -qx 'Develop note.' <<<"$readme" && grep -q 'qs:version.*6\.2\.0' <<<"$readme" &&
	! grep -q 'qs:version.*6\.1\.0' <<<"$readme" && grep -q '<name>app (develop)</name>' <<<"$pom" &&
	grep -q '<version>6\.2\.0</version>' <<<"$pom" && ! grep -q '<version>6\.1\.0</version>' <<<"$pom" &&
	[ "$(git show develop:VERSION)" = 6.2.0 ] && ! git grep -q '^<<<<<<<' develop -- README.md pom.xml &&
	ok "publicar: develop's edits next to the badge and the pom version are kept; badge, pom and VERSION are the RELEASE's" ||
	fail "release-owned lines: $out / $readme / $pom"

# --- a release commit that also changes another line: stop, nothing moved ----------------------
released_version 6.3.0 r r.txt 'from r' "feat(r): add module r" "2020-03-01T10:00:00"
plumb_commit both 6.3.0/RELEASE README.md "$(git show 6.3.0/RELEASE:README.md | sed '1s/.*/# sandbox (release)/')" \
	"docs(readme): reword the title" >/dev/null
plumb_commit both develop README.md "$(git show develop:README.md | sed '1s/.*/# sandbox (develop)/')" \
	"docs: reword the title on develop" >/dev/null
before="$(refs_state)"
out="$(git publicar --version 6.3.0 --yes 2>&1)" && fail "publicar solved a conflict on a line that is not release-owned"
grep -q 'conflict while rebasing 6.3.0/RELEASE onto develop' <<<"$out" && grep -q 'README.md' <<<"$out" &&
	grep -q 'not only on release-owned lines' <<<"$out" && [ "$(refs_state)" = "$before" ] &&
	[ -d "$(git rev-parse --git-path rebase-merge)" ] && grep -q '^<<<<<<<' README.md &&
	ok "publicar: a release commit whose conflict touches another README line stops with the steps; nothing moved" ||
	fail "stop on a non-release line: $out"

# --- the publish state after git rebase --abort: forgotten by the next run, or by --reset -------
from="$(git config qs.publish.6.3.0.from || true)"
out="$(git publicar --reset --version 6.3.0 --yes 2>&1)" && fail "publicar --reset ran while the rebase is stopped"
grep -q 'a rebase is stopped' <<<"$out" && [ "$(git config qs.publish.6.3.0.from || true)" = "$from" ] && [ -n "$from" ] &&
	ok "publicar --reset is refused while the rebase is stopped; the state is kept" || fail "reset while stopped: $out"
git rebase --abort
git checkout -q develop
out="$(git publicar --version 6.3.0 --yes 2>&1)" && fail "publicar 6.3.0 passed the conflict"
grep -q 'stale publish state of 6.3.0 is cleared' <<<"$out" && grep -q 'conflict while rebasing' <<<"$out" &&
	ok "publicar after git rebase --abort clears the stale qs.publish.6.3.0.from first" || fail "stale state: $out"
git rebase --abort
git checkout -q develop
[ -n "$(git config qs.publish.6.3.0.from || true)" ] || fail "fixture: no publish state after the second stop"
out="$(git publicar --reset --version 6.3.0 --yes 2>&1)" || fail "publicar --reset: $out"
grep -q 'publish state of 6.3.0 forgotten' <<<"$out" && [ -z "$(git config --get-regexp '^qs\.publish\.' || true)" ] &&
	[ "$(git rev-parse 6.3.0/RELEASE)" = "$(git rev-parse origin/6.3.0/RELEASE)" ] &&
	ok "publicar --reset --version 6.3.0 forgets the publish state; RELEASE untouched" || fail "reset: $out"
out="$(git publicar --reset --version 6.3.0 --yes 2>&1)" || fail "publicar --reset again: $out"
grep -q 'nothing to reset' <<<"$out" && ok "publicar --reset with no state: nothing to reset" || fail "reset again: $out"
