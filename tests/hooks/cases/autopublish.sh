#!/usr/bin/env bash
# Cases of publish on create (6.0.0 autopublish task, PB1-PB9): every branch a suite command
# creates is pushed to origin with upstream through qs_publish_new; policy and QS_PUBLISH turn it
# off; failures only warn; renames go to origin in one atomic push under a lease.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash
export GIT_TERMINAL_PROMPT=1

SPY="$CASE_REPO/.git/spy.log"
FAILF="$CASE_REPO/.git/spy.fail"

# install_spy: put a pre-push hook in front of the suite's: it logs every push (one PUSH line, the
# ref lines and the GIT_TERMINAL_PROMPT value) and refuses while the file spy.fail exists.
# Arguments: none. Returns: 0.
install_spy() {
	local h=.git/hooks/pre-push
	mv "$h" "$h.suite"
	cat >"$h" <<EOF
#!/bin/sh
in="\$(cat)"
echo "PUSH prompt=\${GIT_TERMINAL_PROMPT:-unset}" >>"$SPY"
printf '%s\n' "\$in" >>"$SPY"
[ ! -e "$FAILF" ] || { echo "refused by the spy" >&2; exit 1; }
printf '%s\n' "\$in" | "$h.suite" "\$@"
EOF
	chmod +x "$h"
}

# published BRANCH: BRANCH is on origin at the local tip and its upstream is origin/BRANCH.
# Arguments: $1 branch. Returns: 0 when published, 1 otherwise.
published() {
	[ "$(git ls-remote origin "refs/heads/$1" | cut -f1)" = "$(git rev-parse "refs/heads/$1")" ] &&
		[ "$(git rev-parse --abbrev-ref "$1@{u}" 2>/dev/null)" = "origin/$1" ]
}

# on_origin BRANCH: origin has the branch. Arguments: $1 branch. Returns: 0 or 1.
on_origin() { [ -n "$(git ls-remote origin "refs/heads/$1")" ]; }

# pushes: the number of pushes the spy saw. Returns: 0; prints the count.
pushes() { grep -c '^PUSH' "$SPY" || true; }

# --- PB1 every creating command publishes
git np 6.0.0 >/dev/null 2>&1
published 6.0.0/ORIGINAL && ok "PB1 git np version" || fail "PB1 version not published"
git np ot1 >/dev/null 2>&1
published 6.0.0/ot1/ORIGINAL && ok "PB1 git np ot1" || fail "PB1 ot1 not published"
git nr a >/dev/null 2>&1
published 6.0.0/ot1/a && ok "PB1 git nr a" || fail "PB1 a not published"
git checkout -q 6.0.0/ot1/ORIGINAL
git nv 6.0.1 --from 6.0.0/ot1/ORIGINAL >/dev/null 2>&1
published 6.0.1/ORIGINAL && published 6.0.1/ot1/ORIGINAL && ok "PB1 git nv publishes the whole copy" || fail "PB1 nv not published"
install_spy
: >"$SPY"
printf '6.0.0\n  ot2\n    t1\n    t2\n    t3\n' | git es >/dev/null 2>&1
for b in 6.0.0/ot2/ORIGINAL 6.0.0/ot2/t1 6.0.0/ot2/t2 6.0.0/ot2/t3; do published "$b" || fail "PB1 es: $b not published"; done
[ "$(pushes)" = 1 ] && ok "PB1 git es publishes 1 OT + 3 tasks in ONE push" || fail "PB1 es pushes: $(pushes)"
git checkout -q 6.0.0/ot1/ORIGINAL
git testing crear 6.0.0/ot1/a --nivel 6.0.0/ot1 >/dev/null 2>&1
published 6.0.0/ot1/TESTING && ok "PB1 git testing crear" || fail "PB1 TESTING not published"

# --- PB5 the push runs pre-push, without prompts and without --no-verify
: >"$SPY"
git checkout -q 6.0.0/ot1/ORIGINAL
git nr pb5 >/dev/null 2>&1
grep -q '^PUSH prompt=0$' "$SPY" && grep -q 'refs/heads/6.0.0/ot1/pb5 ' "$SPY" && ok "PB5 pre-push saw the ref, GIT_TERMINAL_PROMPT=0" || fail "PB5 spy: $(cat "$SPY")"
! grep -rn -e '--no-verify' "$SUITE/scripts/git-rama.sh" "$SUITE/scripts/git-testing.sh" "$SUITE/scripts/git-flow-lib.sh" |
	grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -q 'git .*push' && ok "PB5 the scripts never push with --no-verify" || fail "PB5 --no-verify in a script"

# --- PB2 off by environment and by policy
: >"$SPY"
git checkout -q 6.0.0/ot1/ORIGINAL
out="$(QS_PUBLISH=0 git nr off2 2>&1)"
! on_origin 6.0.0/ot1/off2 && ! git rev-parse -q --verify 6.0.0/ot1/off2@\{u\} >/dev/null 2>&1 && ! grep -qi 'warn\|stays local' <<<"$out" &&
	[ "$(pushes)" = 0 ] && ok "PB2 QS_PUBLISH=0: nothing on origin, no upstream, no warning" || fail "PB2 env: $out"
git checkout -q 6.0.0/ot1/ORIGINAL
printf "QS_BR_PUBLISH='0'\n" >>.git/quality-suite/policy.env
touch .git/quality-suite/policy.env
out="$(git nr off3 2>&1)"
! on_origin 6.0.0/ot1/off3 && ! grep -Eqi 'warn|stays local' <<<"$out" && ok "PB2 publish_on_create false: nothing on origin" || fail "PB2 policy: $out"
git checkout -q 6.0.0/ot1/off3
out="$(git subir 2>&1)" && published 6.0.0/ot1/off3 && ok "PB2 git subir publishes later with upstream" || fail "PB2 subir: $out"
sed -i '/QS_BR_PUBLISH/d' .git/quality-suite/policy.env
git checkout -q 6.0.0/ot1/ORIGINAL

# --- PB3 no remote
git remote rename origin gone
out="$(git nr noremote 2>&1)" && rc=0 || rc=$?
[ "$rc" = 0 ] && git rev-parse -q --verify refs/heads/6.0.0/ot1/noremote >/dev/null && grep -q 'no remote origin' <<<"$out" &&
	ok "PB3 no remote: branch created, exit 0, note printed" || fail "PB3: rc=$rc $out"
git remote rename gone origin
git checkout -q 6.0.0/ot1/ORIGINAL

# --- PB4 offline and refused by pre-push
mv "$CASE_REPO.git" "$CASE_REPO.off"
out="$(git nr offline 2>&1)" && rc=0 || rc=$?
mv "$CASE_REPO.off" "$CASE_REPO.git"
[ "$rc" = 0 ] && git rev-parse -q --verify refs/heads/6.0.0/ot1/offline >/dev/null && [ "$(git branch --show-current)" = 6.0.0/ot1/offline ] &&
	grep -q 'WARN: 6.0.0/ot1/offline is not on origin' <<<"$out" && grep -q 'git subir' <<<"$out" &&
	ok "PB4 offline: branch and checkout stay, WARN with git subir, exit 0" || fail "PB4 offline: rc=$rc $out"
git arbol 6.0.0 2>/dev/null | grep 'ot1/offline' | grep -q '\[local\]' && ok "PB4 git arbol marks it [local]" || fail "PB4 arbol"
out="$(git subir 2>&1)" && published 6.0.0/ot1/offline && ok "PB4 git subir publishes it with upstream" || fail "PB4 subir: $out"
git checkout -q 6.0.0/ot1/ORIGINAL
: >"$FAILF"
out="$(git nr refused 2>&1)" && rc=0 || rc=$?
rm -f "$FAILF"
[ "$rc" = 0 ] && [ "$(git branch --show-current)" = 6.0.0/ot1/refused ] && ! on_origin 6.0.0/ot1/refused &&
	grep -q 'WARN: 6.0.0/ot1/refused is not on origin' <<<"$out" && ok "PB4 refused by pre-push: only a WARN" || fail "PB4 refused: rc=$rc $out"
out="$(git subir 2>&1)" && published 6.0.0/ot1/refused && ok "PB4 git subir publishes after the refusal" || fail "PB4 subir 2: $out"
git checkout -q 6.0.0/ot1/ORIGINAL

# --- PB6 convertir-padre renames on origin in one atomic push under a lease
git checkout -q 6.0.0/ot1/a
git convertir-padre >/dev/null 2>&1
on_origin 6.0.0/ot1/a/ORIGINAL && ! on_origin 6.0.0/ot1/a && published 6.0.0/ot1/a/ORIGINAL &&
	ok "PB6 origin has a/ORIGINAL, not a; upstream set" || fail "PB6 convertir"
git nr child >/dev/null 2>&1
published 6.0.0/ot1/a/child && ok "PB6 the child of the converted parent is published" || fail "PB6 child"
# lost lease: a second clone moves origin's 'pb6' while the rename push is under way (the spy hook)
git checkout -q 6.0.0/ot1/ORIGINAL
git nr pb6 >/dev/null 2>&1
tip="$(git ls-remote origin refs/heads/6.0.0/ot1/pb6 | cut -f1)"
git clone -q "$CASE_REPO.git" "$CASE_REPO.two"
(
	cd "$CASE_REPO.two"
	git config user.email t@example.com
	git config user.name tester
	git checkout -q 6.0.0/ot1/pb6
	printf 'x\n' >two.txt
	git add two.txt
	git -c core.hooksPath=/dev/null commit -q -m "chore: second clone"
)
mv .git/hooks/pre-push .git/hooks/pre-push.spy
cat >.git/hooks/pre-push <<EOF
#!/bin/sh
cat >/dev/null
git -C "$CASE_REPO.two" push -q origin 6.0.0/ot1/pb6 || exit 0
exit 0
EOF
chmod +x .git/hooks/pre-push
out="$(git convertir-padre 2>&1)" && rc=0 || rc=$?
mv .git/hooks/pre-push.spy .git/hooks/pre-push
moved="$(git ls-remote origin refs/heads/6.0.0/ot1/pb6 | cut -f1)"
[ "$moved" != "$tip" ] && [ -n "$moved" ] && ! on_origin 6.0.0/ot1/pb6/ORIGINAL &&
	git rev-parse -q --verify refs/heads/6.0.0/ot1/pb6/ORIGINAL >/dev/null && grep -q 'Ask the human' <<<"$out" &&
	ok "PB6 lost lease: origin untouched, local rename kept, the human is asked" || fail "PB6 lease: rc=$rc moved=$moved tip=$tip $out"

# --- PB8 the default is in every place the policy lives
grep -q 'QS_BR_PUBLISH=1' "$SUITE/scripts/git-flow-lib.sh" && grep -q '"publish_on_create"' "$SUITE/schema/quality-rules.schema.json" &&
	grep -q 'publish_on_create' "$SUITE/docs/QUALITY-RULES.md" && ok "PB8 default in the lib, the schema and the docs" || fail "PB8 default"

# --- PB9 permissions of the template
python3 - "$SUITE/ai-template/.claude/settings.json" <<'PY' && ok "PB9 settings.json: ask/deny rows for git push" || fail "PB9 settings"
import json, sys
perm = json.load(open(sys.argv[1]))["permissions"]
assert "Bash(git push:*)" in perm["ask"], perm
for row in ("Bash(git push --no-verify:*)", "Bash(git release:*)"):
    assert row in perm["deny"], row
assert not [r for r in perm["allow"] if r.startswith("Bash(git push")], perm["allow"]
PY
