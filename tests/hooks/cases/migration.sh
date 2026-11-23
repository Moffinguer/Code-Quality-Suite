#!/usr/bin/env bash
# Cases of the MIGRATION special branch (6.0.0 migration_branch task, ACs MG1-MG6): git np
# --migracion and git migracion create '<v>/MIGRATION', convertir-padre gives its children, git
# integra squashes it into '<v>/ORIGINAL' as one 'build: <subject>' commit and removes the subtree
# (local and origin), DOCS appears, the lock is gone and the changelog line says MIGRATION.
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

# remote_has REF: succeed when origin has the branch REF. Arguments: $1 branch.
remote_has() { git ls-remote --exit-code --heads origin "refs/heads/$1" >/dev/null 2>&1; }

V=6.0.0
M="$V/MIGRATION"
case_sandbox squash

# --- MG1: git np --migracion, git migracion, and where they are refused --------------------------
git np "$V" --migracion >/dev/null 2>&1 || fail "git np $V --migracion"
git rev-parse -q --verify "refs/heads/$V/ORIGINAL" >/dev/null && git rev-parse -q --verify "refs/heads/$M" >/dev/null &&
	[ "$(git rev-parse "$M")" = "$(git rev-parse "$V/ORIGINAL")" ] && [ "$(git branch --show-current)" = "$M" ] &&
	ok "MG1: git np --migracion makes $V/ORIGINAL and $M (checked out) at the same commit" || fail "MG1: np --migracion"
[ "$(git rev-list --count "develop..$V/ORIGINAL")" -ge 1 ] &&
	ok "MG1: $V/ORIGINAL carries the version commit" || fail "MG1: version commit"
out="$(git migracion 2>&1)" && fail "MG1: git migracion on MIGRATION accepted"
out="$(git migracion "$V" 2>&1)" && fail "MG1: second git migracion accepted"
grep -q 'open MIGRATION' <<<"$out" && ok "MG1: an open MIGRATION is not created twice" || fail "MG1: twice: $out"
git checkout -q "$V/ORIGINAL"
out="$(git np ot1 2>&1)" && fail "MG1: git np ot1 accepted under the lock"
grep -q 'open MIGRATION' <<<"$out" && ok "MG1: the lock refuses git np ot1" || fail "MG1: lock: $out"

git checkout -q develop
git np 6.1.0 >/dev/null 2>&1 || fail "np 6.1.0"
git migracion >/dev/null 2>&1 || fail "git migracion on a fresh ORIGINAL"
[ "$(git rev-parse 6.1.0/MIGRATION)" = "$(git rev-parse 6.1.0/ORIGINAL)" ] && [ "$(git branch --show-current)" = 6.1.0/MIGRATION ] &&
	ok "MG1: git migracion on a fresh ORIGINAL does the same" || fail "MG1: migracion"

git checkout -q develop
git np 6.2.0 >/dev/null 2>&1 && git np ot1 >/dev/null 2>&1 || fail "np 6.2.0/ot1"
git checkout -q 6.2.0/ORIGINAL
out="$(git migracion 2>&1)" && fail "MG1: git migracion accepted once ot1 exists"
grep -q 'other branches' <<<"$out" && ! git rev-parse -q --verify refs/heads/6.2.0/MIGRATION >/dev/null &&
	ok "MG1: git migracion refused once 6.2.0/ot1 exists" || fail "MG1: refused: $out"
out="$(git nr x --migracion 2>&1)" && fail "MG1: git nr --migracion accepted"
grep -q 'migracion' <<<"$out" && ok "MG1: --migracion only with git np from develop" || fail "MG1: nr: $out"

# --- MG6: no --migracion, no MIGRATION, no lock ---------------------------------------------------
git checkout -q develop
git np 6.3.0 >/dev/null 2>&1 && git np ot1 >/dev/null 2>&1 || fail "MG6: np 6.3.0/ot1"
! git rev-parse -q --verify refs/heads/6.3.0/MIGRATION >/dev/null &&
	ok "MG6: git np without --migracion makes no MIGRATION and takes no lock" || fail "MG6"

# --- MG2: convertir-padre and children -------------------------------------------------------------
git checkout -q "$M"
git push -q origin "$M" 2>/dev/null || fail "push $M"
git convertir-padre --yes >/dev/null 2>&1 || fail "convertir-padre on MIGRATION"
MO="$M/ORIGINAL"
git rev-parse -q --verify "refs/heads/$MO" >/dev/null && ! git rev-parse -q --verify "refs/heads/$M" >/dev/null &&
	ok "MG2: git convertir-padre on MIGRATION gives $MO" || fail "MG2: convert"
git push -q origin "$MO" 2>/dev/null || fail "push $MO"
for c in java17 spring-boot-3; do
	git checkout -q "$MO"
	out="$(git nr "$c" 2>&1)" || fail "MG2: git nr $c under $MO: $out"
	add_commit "$c.txt" "$c" "build: $c"
	git push -q origin "$M/$c" 2>/dev/null || fail "push $c"
done
git checkout -q "$M/java17"
git integra --yes -m "build: move to java 17" >/dev/null 2>&1 || fail "MG2: integra java17"
git checkout -q "$M/spring-boot-3"
git integra --yes -m "build: move to boot 3" >/dev/null 2>&1 || fail "MG2: integra spring-boot-3"
[ "$(git rev-list --count --parents -n1 "$MO" | wc -l)" = 1 ] && [ "$(git log -1 --format='%P' "$MO" | wc -w)" = 1 ] &&
	[ "$(git log -1 --format=%s "$MO")" = "build: move to boot 3" ] &&
	ok "MG2: the children integrate into $MO as single-parent squashes" || fail "MG2: squashes"

# --- MG3: the MIGRATION squash --------------------------------------------------------------------
git checkout -q "$MO"
git nr late >/dev/null 2>&1 || fail "nr late"
add_commit late.txt late "build: late step"
git checkout -q "$MO"
before="$(git rev-parse "$V/ORIGINAL")"
out="$(git integra --yes -m "Migrate to Java 17" 2>&1)" && fail "MG3: integrated with a pending child"
grep -q 'not integrated' <<<"$out" && grep -q "$M/late" <<<"$out" && [ "$(git rev-parse "$V/ORIGINAL")" = "$before" ] &&
	ok "MG3: refused while a child is pending, naming it" || fail "MG3: pending: $out"
git checkout -q "$M/late"
git integra --yes -m "build: late step" >/dev/null 2>&1 || fail "MG3: integra late"
git checkout -q "$MO"
out="$(git integra --yes -m "feat: migrate" 2>&1)" && fail "MG3: a feat subject was accepted"
grep -q "build: <subject>" <<<"$out" && ok "MG3: another Conventional type is refused" || fail "MG3: feat: $out"
git integra --yes -m "Migrate to Java 17 and Boot 3" -m "Why: the platform moves." >/dev/null 2>&1 || fail "MG3: integra $MO"
[ "$(git rev-list --count "$before..$V/ORIGINAL")" = 1 ] && [ "$(git log -1 --format=%P "$V/ORIGINAL" | wc -w)" = 1 ] &&
	[ "$(git log -1 --format=%s "$V/ORIGINAL")" = "build: Migrate to Java 17 and Boot 3" ] &&
	ok "MG3: one new single-parent commit 'build: <subject>' on $V/ORIGINAL" || fail "MG3: commit"
body="$(git log -1 --format=%B "$V/ORIGINAL")"
grep -q '^Commits:' <<<"$body" && grep -q '^- [0-9a-f]* build: move to java 17' <<<"$body" &&
	grep -q '^  - [0-9a-f]* build: java17' <<<"$body" && grep -q '^Files:' <<<"$body" &&
	grep -q "^Squashed: $MO [0-9a-f]\{40\}" <<<"$body" &&
	ok "MG3: the body has Commits: (nested), Files: and Squashed:" || fail "MG3: body: $body"

# --- MG4: subtree gone, DOCS there, lock released --------------------------------------------------
[ -z "$(git for-each-ref "refs/heads/$M" "refs/heads/$M/")" ] && ! remote_has "$M" && ! remote_has "$MO" &&
	[ -z "$(git ls-remote --heads origin "refs/heads/$M/*")" ] &&
	ok "MG4: no ref under $M, local or origin" || fail "MG4: refs left"
git rev-parse -q --verify "refs/heads/$V/DOCS" >/dev/null && [ "$(git rev-parse "$V/DOCS")" = "$(git rev-parse "$V/ORIGINAL")" ] &&
	ok "MG4: $V/DOCS exists at $V/ORIGINAL (DOCS mode)" || fail "MG4: DOCS"
git np ot1 >/dev/null 2>&1 && ok "MG4: git np ot1 works after the squash" || fail "MG4: np ot1"

# --- MG5: the changelog line ----------------------------------------------------------------------
git checkout -q "$V/ORIGINAL"
base="$(git rev-parse "develop")"
tip="$(git rev-parse "$V/ORIGINAL")"
short="$(git rev-parse --short=7 "$V/ORIGINAL")"
notes="$(python3 "$SUITE/engine/qs.py" release-notes --version "$V" --tip "$tip" --base "$base" 2>"$T/mg.err")" || fail "MG5: release-notes"
printf '%s\n' "$notes" | grep -qxF -- "- Migrate to Java 17 and Boot 3 ($short; MIGRATION)" &&
	ok "MG5: one Changed line '(<hash>; MIGRATION)'" || fail "MG5: line: $notes"
grep -q 'change without OT' "$T/mg.err" && fail "MG5: 'change without OT' warning" || ok "MG5: no 'change without OT' warning"
