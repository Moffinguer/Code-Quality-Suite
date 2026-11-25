#!/usr/bin/env bash
# scripts/qs-common.sh and scripts/hook-lib.sh in isolation: qs_die / qs_say output, qs_ref_exists,
# qs_confirm, qs_hook_env (both env-load variants) and qs_hook_flow_lib (loaded and lib missing).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# --- qs-common.sh ---
out="$(QS_TAG=demo bash -c '. "$1/scripts/qs-common.sh"; qs_say hello world' _ "$SUITE")"
[ "$out" = "[demo] hello world" ] && ok "qs_say prints [tag] message" || fail "qs_say: $out"

rc=0
QS_TAG=demo bash -c '. "$1/scripts/qs-common.sh"; qs_die boom now' _ "$SUITE" >"$W/o" 2>"$W/e" || rc=$?
[ "$rc" = 1 ] && [ ! -s "$W/o" ] && [ "$(cat "$W/e")" = "[demo] boom now" ] &&
	ok "qs_die writes to stderr and exits 1" || fail "qs_die rc=$rc"

git init -q -b main "$W/r"
git -C "$W/r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: x"
(
	cd "$W/r"
	# shellcheck source=scripts/qs-common.sh
	. "$SUITE/scripts/qs-common.sh"
	qs_ref_exists main && ! qs_ref_exists nope && ! qs_ref_exists refs/heads/nope
) && ok "qs_ref_exists" || fail "qs_ref_exists"

bash -c '. "$1/scripts/qs-common.sh"; YES=1 qs_confirm "sure?"' _ "$SUITE" >/dev/null 2>&1 &&
	ok "qs_confirm YES=1 answers yes" || fail "qs_confirm YES=1"

# --- hook-lib.sh: qs_hook_env ---
mkdir -p "$W/hooks"
printf 'PLAIN_VAR=1\n' >"$W/hooks/quality-suite.env"
# why: the probe is script text for the inner bash, so it must not expand here
# shellcheck disable=SC2016
probe='. "$1/scripts/hook-lib.sh"; export QS_HOOK_DIR="$2"; qs_hook_env $3; echo "$HOOK_DIR|${QS_HOOK_DIR-unset}"; sh -c "echo child=\${PLAIN_VAR:-none}"'
out="$(bash -c "$probe" _ "$SUITE" "$W/hooks" "")"
[ "$out" = "$W/hooks|unset
child=none" ] && ok "qs_hook_env: HOOK_DIR set, QS_HOOK_DIR unset, no export" || fail "qs_hook_env plain: $out"
out="$(bash -c "$probe" _ "$SUITE" "$W/hooks" --export)"
[ "$out" = "$W/hooks|unset
child=1" ] && ok "qs_hook_env --export: settings reach child processes" || fail "qs_hook_env --export: $out"
out="$(bash -c "$probe" _ "$SUITE" "$W/none" "")"
[ "$out" = "$W/none|unset
child=none" ] && ok "qs_hook_env: missing env file is fine" || fail "qs_hook_env missing: $out"

# --- hook-lib.sh: qs_hook_flow_lib ---
rc=0
QUALITY_SUITE_DIR="$W/no-suite" bash -c '. "$1/scripts/hook-lib.sh"; qs_hook_flow_lib' _ "$SUITE" || rc=$?
[ "$rc" = 1 ] && ok "qs_hook_flow_lib returns 1 when git-flow-lib.sh is missing" || fail "flow lib missing rc=$rc"

out="$(cd "$W/r" && QUALITY_SUITE_DIR="$SUITE" QS_POLICY_NO_DOCKER=1 bash -c \
	'. "$1/scripts/hook-lib.sh"; qs_hook_flow_lib && echo "loaded enforce=${QS_BR_ENFORCE:-unset}"' _ "$SUITE")"
case "$out" in
*"loaded enforce="[a-z]*) [ "$out" != "loaded enforce=unset" ] && ok "qs_hook_flow_lib loads the policy" || fail "policy not loaded: $out" ;;
*) fail "qs_hook_flow_lib: $out" ;;
esac
