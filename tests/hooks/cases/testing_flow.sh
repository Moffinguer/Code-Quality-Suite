#!/usr/bin/env bash
# Flow gate of the TESTING sandbox (5.0.0-RC1/git/testing_branch): with branches.flow = merge (4.x)
# the 'git testing' commands are refused with the reason and create nothing, the TESTING leaf is an
# ordinary segment (valid names, not a sandbox); with branches.flow = squash the leaf is reserved.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox merge

F=1.0.0/700
WHY="TESTING needs branches.flow: squash"

# --- flow = merge: every sandbox command is refused with the reason, nothing is created ----------
for sub in "crear develop --nivel $F" "estado $F" "repartir $F"; do
	# shellcheck disable=SC2086
	if out="$(git testing $sub 2>&1)"; then fail "merge: git testing $sub not refused"; fi
	grep -q "$WHY" <<<"$out" || fail "merge: no reason for git testing $sub: $out"
done
! git rev-parse -q --verify "refs/heads/$F/TESTING" >/dev/null &&
	ok "merge: git testing crear/estado/repartir refused with '$WHY', nothing created" ||
	fail "merge: a TESTING branch was created"

# --- flow = merge: the leaf is an ordinary segment --------------------------------------------
case_flow_eval valid_branch_name "$F/TESTING" >/dev/null && case_flow_eval valid_branch_name "$F/Testing/x" >/dev/null &&
	! case_flow_eval is_testing_branch "$F/TESTING" && ! case_flow_eval testing_reserved_segment Testing &&
	ok "merge: TESTING is an ordinary segment (valid names, no sandbox)" || fail "merge: TESTING names"

# --- flow = squash: the same leaf is the sandbox and reserved ----------------------------------
case_sandbox squash
case_flow_eval valid_branch_name "$F/TESTING" >/dev/null && ! case_flow_eval valid_branch_name "$F/TESTING/x" >/dev/null &&
	! case_flow_eval valid_branch_name "$F/Testing/x" >/dev/null && case_flow_eval is_testing_branch "$F/TESTING" &&
	case_flow_eval testing_reserved_segment Testing &&
	ok "squash: <level>/TESTING is the sandbox leaf; other TESTING segments refused" || fail "squash: TESTING names"
out="$(git testing estado "$F" 2>&1 || true)"
grep -q "$WHY" <<<"$out" && fail "squash: git testing still refused by flow: $out"
ok "squash: git testing is not refused by the flow"
