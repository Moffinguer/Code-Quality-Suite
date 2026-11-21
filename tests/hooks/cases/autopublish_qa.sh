#!/usr/bin/env bash
# QA cases of publish on create (6.0.0 autopublish): the real `branches.publish_on_create: false`
# key in .quality-rules.json, no or offline origin for renames, a lost lease never touches origin,
# partial refusals of a rename, and the deletions of the version release under a lease.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

# on_origin BRANCH: origin has the branch. Arguments: $1 branch. Returns: 0 or 1.
on_origin() { [ -n "$(git ls-remote origin "refs/heads/$1")" ]; }

# set_rule VALUE: write branches.publish_on_create into .quality-rules.json.
# Arguments: $1 the JSON boolean (true or false). Returns: 0.
set_rule() {
	python3 - "$1" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("branches", {})["publish_on_create"] = sys.argv[1] == "true"
json.dump(d, open(p, "w"), indent=2)
PY
	# why: the policy file is read again when the rules file is newer than policy.env
	touch .quality-rules.json
}

git np 6.0.0 >/dev/null 2>&1
git np ot1 >/dev/null 2>&1

# --- the real key: false keeps every creator local, silently, and git subir publishes later
set_rule false
out="$(git nr k1 2>&1)"
! on_origin 6.0.0/ot1/k1 && ! grep -Eqi 'warn|stays local' <<<"$out" &&
	ok "QA key false (real rules file): git nr stays local, no warning" || fail "QA key false nr: $out"
git checkout -q 6.0.0/ot1/ORIGINAL
out="$(git nr k2 2>&1)"
git checkout -q 6.0.0/ot1/ORIGINAL
git np ot9 >/dev/null 2>&1 || true
! on_origin 6.0.0/ot9/ORIGINAL && ok "QA key false: git np stays local" || fail "QA key false np"
git checkout -q 6.0.0/ot1/k2
out="$(git subir 2>&1)" && [ "$(git rev-parse --abbrev-ref '6.0.0/ot1/k2@{u}')" = origin/6.0.0/ot1/k2 ] &&
	ok "QA key false: git subir publishes with upstream (-u)" || fail "QA subir: $out"
# convertir-padre of a branch on origin with the key false: asks (QS_NO_PROMPT / no tty = refuses)
git checkout -q 6.0.0/ot1/k2
out="$(git convertir-padre </dev/null 2>&1)" && rc=0 || rc=$?
{ [ "$rc" != 0 ] && on_origin 6.0.0/ot1/k2 && ! on_origin 6.0.0/ot1/k2/ORIGINAL; } ||
	{ [ "$rc" = 0 ] && on_origin 6.0.0/ot1/k2/ORIGINAL && ! on_origin 6.0.0/ot1/k2; } &&
	ok "QA key false: convertir-padre is all or nothing on origin (rc=$rc)" || fail "QA convertir false: rc=$rc $out"
set_rule true

# --- convertir-padre with an offline origin: warning, local rename kept, exit 0, origin untouched
git checkout -q 6.0.0/ot1/ORIGINAL
git nr off1 >/dev/null 2>&1
on_origin 6.0.0/ot1/off1 || fail "QA setup: off1 not published"
mv "$CASE_REPO.git" "$CASE_REPO.off"
out="$(git convertir-padre 2>&1)" && rc=0 || rc=$?
mv "$CASE_REPO.off" "$CASE_REPO.git"
[ "$rc" = 0 ] && git rev-parse -q --verify refs/heads/6.0.0/ot1/off1/ORIGINAL >/dev/null && on_origin 6.0.0/ot1/off1 &&
	! on_origin 6.0.0/ot1/off1/ORIGINAL && ok "QA offline convertir-padre: exit 0, local rename kept, origin untouched" ||
	fail "QA offline convertir: rc=$rc $out"

# --- convertir-padre without origin: local rename, no error
git checkout -q 6.0.0/ot1/ORIGINAL
git nr nor1 >/dev/null 2>&1
git remote rename origin gone
out="$(git convertir-padre 2>&1)" && rc=0 || rc=$?
git remote rename gone origin
[ "$rc" = 0 ] && git rev-parse -q --verify refs/heads/6.0.0/ot1/nor1/ORIGINAL >/dev/null &&
	ok "QA no origin: convertir-padre renames locally, exit 0" || fail "QA no origin convertir: rc=$rc $out"

# --- version release: a deletion under a lease; another clone pushes to the OT while it runs
case_sandbox squash
V=9.2.0
git np "$V" >/dev/null 2>&1 && git np 800 >/dev/null 2>&1 && git nr a >/dev/null 2>&1 || fail "QA release tree"
printf 'A = 1\n' >a.py
git add a.py
git commit -q -m "feat: add a" || fail "QA commit a"
git integra --yes -m "feat(a): module a" >/dev/null 2>&1 || fail "QA integra a"
git checkout -q "$V/800/ORIGINAL"
git release --yes >/dev/null 2>&1 || fail "QA OT release"
git checkout -q "$V/ORIGINAL"
git clone -q "$CASE_REPO.git" "$CASE_REPO.two"
(
	cd "$CASE_REPO.two"
	git config user.email t@example.com
	git config user.name tester
	git checkout -q "$V/ORIGINAL"
	printf 'Z\n' >two.txt
	git add two.txt
	git -c core.hooksPath=/dev/null commit -q -m "chore: second clone"
)
tip="$(git ls-remote origin "refs/heads/$V/ORIGINAL" | cut -f1)"
mv .git/hooks/pre-push .git/hooks/pre-push.suite
cat >.git/hooks/pre-push <<HOOK
#!/bin/sh
cat >/dev/null
git -C "$CASE_REPO.two" push -q origin "$V/ORIGINAL" >/dev/null 2>&1
exit 0
HOOK
chmod +x .git/hooks/pre-push
out="$(git release --version "$V" --yes 2>&1)" && rc=0 || rc=$?
mv .git/hooks/pre-push.suite .git/hooks/pre-push
moved="$(git ls-remote origin "refs/heads/$V/ORIGINAL" | cut -f1)"
{ [ "$moved" != "$tip" ] && [ -n "$moved" ] && ! on_origin "$V/RELEASE"; } &&
	ok "QA version release, lost lease on the deletion: origin keeps the moved ORIGINAL and gets nothing (rc=$rc)" ||
	fail "QA version lease: rc=$rc moved=$moved tip=$tip $out"

# --- the integra pre-rebase guard still holds for a PUBLISHED ORIGINAL (integra.sh runs it with
# QS_PUBLISH=0, where the ORIGINAL is local): parent moved ahead, a child pending -> refused
case_sandbox squash
git np 9.0.0 >/dev/null 2>&1
git np 500 >/dev/null 2>&1
git np RF1 >/dev/null 2>&1
git nr a >/dev/null 2>&1
printf 'A = 1\n' >a.py
git add a.py
git commit -q -m "feat: add a" || fail "QA pre-rebase: commit a"
git checkout -q 9.0.0/500/ORIGINAL
printf 'P = 1\n' >p.py
git add p.py
git commit -q -m "feat: parent moves" || fail "QA pre-rebase: commit parent"
git push -q origin 9.0.0/500/ORIGINAL 2>/dev/null || fail "QA pre-rebase: push parent"
on_origin 9.0.0/500/RF1/ORIGINAL || fail "QA pre-rebase: RF1 ORIGINAL is not published"
out="$(.git/hooks/pre-rebase 9.0.0/500/ORIGINAL 9.0.0/500/RF1/ORIGINAL 2>&1)" && rc=0 || rc=$?
[ "$rc" != 0 ] && grep -q 'not integrated' <<<"$out" && grep -q '9.0.0/500/RF1/a' <<<"$out" &&
	ok "QA pre-rebase refuses a PUBLISHED ORIGINAL with a pending child" || fail "QA pre-rebase published: rc=$rc $out"

# --- last (a failure stops the case): a pre-push that lets the deletion through but refuses the new
# name (a server rule against new branches does the same): origin must keep the work
case_sandbox squash
git np 6.0.0 >/dev/null 2>&1
git np ot1 >/dev/null 2>&1
git nr part1 >/dev/null 2>&1
tip="$(git rev-parse 6.0.0/ot1/part1)"
mv .git/hooks/pre-push .git/hooks/pre-push.suite
cat >.git/hooks/pre-push <<'HOOK'
#!/bin/sh
in="$(cat)"
case "$in" in *part1/ORIGINAL*) echo "refused new name" >&2; exit 1 ;; esac
exit 0
HOOK
chmod +x .git/hooks/pre-push
out="$(git convertir-padre 2>&1)" && rc=0 || rc=$?
mv .git/hooks/pre-push.suite .git/hooks/pre-push
{ on_origin 6.0.0/ot1/part1 || on_origin 6.0.0/ot1/part1/ORIGINAL; } &&
	ok "QA new name refused by pre-push: the work is still on origin under some name" ||
	fail "QA part-refusal LOST the work on origin (tip $tip): rc=$rc $out"

# --- server side: a pre-receive hook on origin accepts the deletion but refuses the new name (a
# dry run cannot see it): the old name must be put back on origin at the same tip
case_sandbox squash
git np 6.0.0 >/dev/null 2>&1
git np ot1 >/dev/null 2>&1
git nr part2 >/dev/null 2>&1
tip="$(git rev-parse 6.0.0/ot1/part2)"
cat >"$CASE_REPO.git/hooks/pre-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
	case "$ref" in *part2/ORIGINAL) echo "server refuses the new name" >&2; exit 1 ;; esac
done
exit 0
HOOK
chmod +x "$CASE_REPO.git/hooks/pre-receive"
out="$(git convertir-padre 2>&1)" && rc=0 || rc=$?
rm -f "$CASE_REPO.git/hooks/pre-receive"
[ "$(git ls-remote origin refs/heads/6.0.0/ot1/part2 | cut -f1)" = "$tip" ] && ! on_origin 6.0.0/ot1/part2/ORIGINAL &&
	git rev-parse -q --verify refs/heads/6.0.0/ot1/part2/ORIGINAL >/dev/null &&
	ok "QA server refuses the new name after the delete: old name restored at the same tip, local rename kept" ||
	fail "QA server refusal: origin lost or moved 6.0.0/ot1/part2 (tip $tip): rc=$rc $out"
