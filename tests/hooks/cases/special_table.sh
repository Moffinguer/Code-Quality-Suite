#!/usr/bin/env bash
# Case: the special branch table, acceptance criterion TB6 (qs_special_need_squash).
# Runs under tests/hooks/run.sh, which exports SUITE and T and the isolated git settings.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -uo pipefail
. "$SUITE/tests/hooks/case-lib.sh"

# run_need_squash FLOW: call qs_special_need_squash with QS_BR_FLOW set to FLOW.
# Arguments: FLOW (merge or squash). Returns: the function's status; its stderr goes to $ERR.
run_need_squash() {
	QS_BR_FLOW="$1" bash -c '. "$SUITE/scripts/git-flow-lib.sh"; qs_special_need_squash' 2>"$ERR"
}

case_sandbox merge
ERR="$T/special-err.txt"

run_need_squash merge && fail "TB6: merge flow accepted special branches"
grep -q "special branches need the squash flow" "$ERR" &&
	ok "TB6: merge flow refused with its message" || fail "TB6: message missing: $(cat "$ERR")"

run_need_squash squash && ok "TB6: squash flow accepted" || fail "TB6: squash flow refused"
