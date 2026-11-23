#!/usr/bin/env bash
# Case delivery: qs_delivery_resolve (scripts/forge/delivery.sh) for every row of the delivery
# modes table, against a FAKE gh (tests/hooks/fake-gh-forge; never the real GitHub API).
# Covers PP2 (resolution) and PP3 (detection is read-only).
# Standalone: bash tests/hooks/cases/delivery.sh   (also run by tests/hooks/run.sh)
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
SUITE="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() {
	echo "FAIL: delivery: $*" >&2
	exit 1
}
ok() { echo "ok   delivery: $*"; }

export FAKE_GH="$T/gh"
mkdir -p "$FAKE_GH/resp" "$T/bin"
cp "$SUITE/tests/hooks/fake-gh-forge" "$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export GIT_CONFIG_GLOBAL="$T/gitconfig" HOME="$T/home"
: >"$GIT_CONFIG_GLOBAL"
mkdir -p "$HOME"
git init -q "$T/repo"
cd "$T/repo"
git config user.email t@example.com
git config user.name tester
git remote add origin git@github.com:o/r.git

# shellcheck source=scripts/forge/delivery.sh
. "$SUITE/scripts/forge/delivery.sh"

RULES='repos/o/r/rules/branches/develop'
PR_RULE='[{"type": "deletion"}, {"type": "pull_request", "parameters": {}}]'
NO_PR_RULE='[{"type": "deletion"}, {"type": "non_fast_forward"}]'

# resolve MODE [BRANCH]: run qs_delivery_resolve with QS_BR_DELIVERY=MODE; sets OUT_MODE,
# OUT_REASON, OUT_ERR (stderr) and RC.
resolve() {
	local out
	RC=0
	out="$(QS_BR_DELIVERY="$1" qs_delivery_resolve "${2:-develop}" 2>"$T/err")" || RC=$?
	OUT_MODE="$(printf '%s\n' "$out" | sed -n 1p)"
	OUT_REASON="$(printf '%s\n' "$out" | sed -n 2p)"
	OUT_ERR="$(cat "$T/err")"
}

# --- push --------------------------------------------------------------------------------------
resolve push
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] && [ -n "$OUT_REASON" ] && [ ! -e "$FAKE_GH/calls.log" ] &&
	ok "push: push, one reason, no gh call" || fail "push: $RC $OUT_MODE"

# --- pr ---------------------------------------------------------------------------------------
resolve pr
[ "$RC" = 0 ] && [ "$OUT_MODE" = pr ] && ok "pr with provider, gh and login: pr" || fail "pr: $RC $OUT_MODE $OUT_ERR"
touch "$FAKE_GH/loggedout"
resolve pr
[ "$RC" = 1 ] && [ -z "$OUT_MODE" ] && case "$OUT_ERR" in *"gh auth login"*) true ;; *) false ;; esac &&
	ok "pr not logged in: refused naming gh auth login" || fail "pr loggedout: $RC '$OUT_ERR'"
rm "$FAKE_GH/loggedout"
QS_GH_BIN=no-such-gh-program
export QS_GH_BIN
resolve pr
[ "$RC" = 1 ] && [ -z "$OUT_MODE" ] && case "$OUT_ERR" in *"gh is not installed"*) true ;; *) false ;; esac &&
	ok "pr without gh: refused" || fail "pr no gh: $RC '$OUT_ERR'"
unset QS_GH_BIN
git remote set-url origin git@gitlab.com:o/r.git
resolve pr
[ "$RC" = 1 ] && [ -z "$OUT_MODE" ] && case "$OUT_ERR" in *"set branches.delivery to push"*) true ;; *) false ;; esac &&
	ok "pr without provider: refused naming the fix" || fail "pr no provider: $RC '$OUT_ERR'"

# --- auto -------------------------------------------------------------------------------------
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] &&
	[ "$OUT_REASON" = "[publicar] delivery auto: origin host has no forge provider; pushing directly (set branches.delivery to pr or push)" ] &&
	ok "auto with an unknown host: push with the notice line" || fail "auto unknown host: $RC '$OUT_REASON'"
git remote set-url origin git@github.com:o/r.git
: >"$FAKE_GH/calls.log"
printf '%s' "$PR_RULE" >"$FAKE_GH/resp/GET_$(printf '%s' "$RULES" | tr '/?&=:' '_____')"
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = pr ] && ok "auto with a pull_request rule: pr" || fail "auto pr rule: $RC $OUT_MODE"
printf '%s' "$NO_PR_RULE" >"$FAKE_GH/resp/GET_$(printf '%s' "$RULES" | tr '/?&=:' '_____')"
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] && ok "auto without a pull_request rule: push" || fail "auto no rule: $RC $OUT_MODE"
resolve pr
[ "$RC" = 0 ] && [ "$OUT_MODE" = pr ] && ok "pr does not depend on the rule" || fail "pr without rule: $RC $OUT_MODE"
touch "$FAKE_GH/apierror"
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] && case "$OUT_REASON" in "[publicar] delivery auto: "*"could not be read; pushing directly"*) true ;; *) false ;; esac &&
	ok "auto with an API error: push with the notice line" || fail "auto api error: $RC '$OUT_REASON'"
rm "$FAKE_GH/apierror"
touch "$FAKE_GH/loggedout"
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] && case "$OUT_REASON" in *"gh is not logged in"*) true ;; *) false ;; esac &&
	ok "auto not logged in: push with the notice line" || fail "auto loggedout: $RC '$OUT_REASON'"
rm "$FAKE_GH/loggedout"
QS_GH_BIN=no-such-gh-program
export QS_GH_BIN
resolve auto
[ "$RC" = 0 ] && [ "$OUT_MODE" = push ] && case "$OUT_REASON" in *"gh is not installed"*) true ;; *) false ;; esac &&
	ok "auto without gh: push with the notice line" || fail "auto no gh: $RC '$OUT_REASON'"
unset QS_GH_BIN
resolve bogus
[ "$RC" = 1 ] && [ -z "$OUT_MODE" ] && case "$OUT_ERR" in *"invalid branches.delivery"*) true ;; *) false ;; esac &&
	ok "an unknown mode is refused" || fail "bogus mode: $RC"
# why: the default (no QS_BR_DELIVERY) is auto
printf '%s' "$PR_RULE" >"$FAKE_GH/resp/GET_$(printf '%s' "$RULES" | tr '/?&=:' '_____')"
out="$(qs_delivery_resolve develop 2>/dev/null | sed -n 1p)"
[ "$out" = pr ] && ok "default mode is auto" || fail "default mode: $out"

# --- tracked token ----------------------------------------------------------------------------
TOK="dummy-$$-$RANDOM"
printf 'value=%s\n' "$TOK" >leak.txt
git add leak.txt
git commit -q -m "chore: leak"
RC=0
GH_TOKEN=$TOK QS_BR_DELIVERY=auto qs_delivery_resolve develop >"$T/o" 2>"$T/e" || RC=$?
[ "$RC" = 1 ] && [ ! -s "$T/o" ] && ! grep -qF "$TOK" "$T/e" &&
	ok "a tracked token is refused in auto, value not printed" || fail "token auto: $RC"

# --- PP3: read-only ---------------------------------------------------------------------------
[ -s "$FAKE_GH/calls.log" ] || fail "PP3 no call was recorded"
if grep -E '^(POST|PUT|PATCH|DELETE) ' "$FAKE_GH/calls.log" >/dev/null; then fail "PP3 a write call happened"; fi
grep -qv '^GET ' "$FAKE_GH/calls.log" && fail "PP3 a non-GET call: $(grep -v '^GET ' "$FAKE_GH/calls.log" | head -1)"
ok "PP3 detection made only GET calls"
