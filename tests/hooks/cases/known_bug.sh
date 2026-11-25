#!/usr/bin/env bash
# git bug-conocido (7.1.1 known_bugs, ACs KB3, KB4, KB6): a bug found in a released version is
# documented first. The command commits a KNOWN_BUGS.md row on the current branch and copies it
# (cherry-pick -x shape, plumbing only) to develop, every ORIGINAL and every final, pushing each
# with a plain push. The sandbox has main, develop, a version tree with two finals and a second OT.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

V=9.7.0 OT="$V/500"
case_sandbox squash
export QS_PUBLISH=0
printf '# Known bugs\n\n| Date | Where | Symptom | Status |\n| --- | --- | --- | --- |\n' >KNOWN_BUGS.md
git add KNOWN_BUGS.md && git commit -q -m "docs: known bugs" && git push -q origin develop || fail "seed develop"
git np "$V" >/dev/null && git np 500 >/dev/null || fail "tree $OT"
git nr a >/dev/null && case_commit a.py 'A = 1' "feat: add a" && git push -q origin "$OT/a" || fail "final a"
git checkout -q "$OT/ORIGINAL" && git nr b >/dev/null && case_commit b.py 'B = 1' "feat: add b" &&
	git push -q origin "$OT/b" || fail "final b"
git checkout -q "$OT/a"

# --- -n changes nothing ---------------------------------------------------------------------
before="$(git for-each-ref refs/heads refs/remotes | sha1sum)"
out="$(git bug-conocido -n "git x" "it breaks" 2>&1)" && grep -q "$OT/b" <<<"$out" &&
	[ "$(git for-each-ref refs/heads refs/remotes | sha1sum)" = "$before" ] &&
	ok "-n lists the branches and changes nothing" || fail "-n: $out"

# --- the row reaches every branch ------------------------------------------------------------
out="$(git bug-conocido "git x" "it breaks | badly" 2>&1)" || fail "bug-conocido: $out"
c="$(git rev-parse HEAD)"
[ "$(git log -1 --format=%s)" = "docs(bugs): git x" ] &&
	[ "$(git diff --name-only HEAD~1 HEAD)" = KNOWN_BUGS.md ] &&
	git log -1 --format=%B | grep -q "^Known-bug: $(date +%Y-%m-%d) git x$" &&
	ok "first commit: one file, subject and Known-bug trailer" || fail "commit shape"
for b in develop "$V/ORIGINAL" "$OT/ORIGINAL" "$OT/b"; do
	git fetch -q origin
	row="$(git show "origin/$b:KNOWN_BUGS.md" | grep -c 'it breaks \| badly')"
	[ "$row" = 1 ] && [ "$(git rev-list --parents -n1 "origin/$b" | wc -w)" = 2 ] &&
		git log -1 --format=%B "origin/$b" | grep -q "^(cherry picked from commit $c)$" ||
		fail "$b did not get the row: $out"
done
ok "develop, ORIGINALs and the other final got one single-parent copy on origin"
grep -q "$OT/b: ok - on it run: git subir" <<<"$out" && ok "finals are told to git subir" || fail "hint: $out"

# --- idempotent: a second run adds nothing to branches that have it ---------------------------
tip="$(git rev-parse origin/develop)"
git bug-conocido "git y" "second" >/dev/null 2>&1 || fail "second run"
git fetch -q origin
[ "$(git show origin/develop:KNOWN_BUGS.md | grep -c '^| 20')" = 2 ] && [ "$tip" != "$(git rev-parse origin/develop)" ] &&
	ok "a second bug adds its own row" || fail "second row"
