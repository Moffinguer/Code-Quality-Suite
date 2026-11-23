#!/usr/bin/env bash
# git arbol --limpiar (scripts/git-rama.sh), second QA round of 5.0.0-RC1/git/arbol: a lease
# failure (origin moves between the fetch and the push), an empty branch equal to its parent's
# tip, and no deletion without --yes when there is no terminal.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

V=9.1.0 OT="$V/600"
RF="$OT/RF2"

# --- B1 lease failure: origin moves between the fetch and the push (a pre-push hook moves it)
case_fresh_tree "$V" 600 RF2
case_local_has "$RF/a" && case_on_origin "$RF/a" || fail "B1 fixture"
MOVED="$(git commit-tree "$RF/a^{tree}" -p "$RF/a" -m "feat: someone pushed")" || fail "B1 commit-tree"
git push -q origin "$MOVED:refs/heads/tmp-moved" 2>/dev/null || fail "B1 stage the commit on origin"
git push -q origin ":refs/heads/tmp-moved" 2>/dev/null || fail "B1 unstage"
HOOK="$(git rev-parse --git-path hooks/pre-push)"
{
	printf '#!/bin/sh\n'
	printf 'git --git-dir="%s" update-ref "refs/heads/%s" %s\n' "$CASE_REPO.git" "$RF/a" "$MOVED"
	[ ! -f "$HOOK" ] || tail -n +2 "$HOOK"
} >"$HOOK.new"
mv "$HOOK.new" "$HOOK"
chmod +x "$HOOK"
set +e
OUT="$(git arbol --limpiar --yes "$V" 2>&1)"
RC=$?
set -e
[ "$(git -C "$CASE_REPO.git" rev-parse "refs/heads/$RF/a" 2>/dev/null)" = "$MOVED" ] &&
	[ "$RC" != 0 ] && case_local_has "$RF/a" && ! grep -q "deleted '" <<<"$OUT" &&
	grep -q "could not delete on origin" <<<"$OUT" &&
	ok "B1 lease failure keeps origin's new work and the local copy, says so, exits non-zero" ||
	fail "B1 lease: rc=$RC $OUT"

# --- B2 an empty branch (tip = its ORIGINAL's tip) is never cleaned, local or on origin
case_fresh_tree "$V" 600 RF2
git nr e >/dev/null || fail "B2 nr e"
[ "$(git rev-parse "$RF/e")" = "$(git rev-parse "$RF/ORIGINAL")" ] || fail "B2 e is not empty"
git push -q origin "$RF/e" 2>/dev/null || fail "B2 push e"
git checkout -q "$RF/ORIGINAL"
OUT="$(git arbol --limpiar --yes "$V" 2>&1)" || fail "B2 limpiar failed: $OUT"
case_local_has "$RF/e" && case_on_origin "$RF/e" && ! case_local_has "$RF/a" && ! case_on_origin "$RF/a" &&
	ok "B2 empty branch kept (local and origin), integrated one cleaned" || fail "B2 empty: $OUT"

# --- B3 without --yes and without a terminal nothing is deleted
case_fresh_tree "$V" 600 RF2
OUT="$(git arbol --limpiar "$V" 2>&1 </dev/null)" || fail "B3 limpiar failed: $OUT"
case_local_has "$RF/a" && case_on_origin "$RF/a" && grep -q "integrated: $RF/a" <<<"$OUT" &&
	grep -q "nothing deleted" <<<"$OUT" && ok "B3 no --yes, no terminal: listed, nothing deleted" ||
	fail "B3 no yes: $OUT"
