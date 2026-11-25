#!/usr/bin/env bash
# hook-lib.sh - the preamble shared by the git hooks. Source it from a hook once
# QUALITY_SUITE_DIR is known (the hook reads quality-suite.env inline to learn it).

# why: the hooks share the common helpers (qs_ref_exists...) without sourcing them one by one
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/qs-common.sh"

# qs_hook_env [--export]: locate the hook folder and load its settings file.
# Arguments: --export loads quality-suite.env with "set -a", so child scripts see the settings.
# Sets HOOK_DIR (QS_HOOK_DIR from the repo wrapper, else the folder of the running hook) and
# unsets QS_HOOK_DIR so it is not inherited. Return value: 0 (a missing env file is fine).
qs_hook_env() {
	local export_all=0
	[ "${1:-}" = --export ] && export_all=1
	HOOK_DIR="${QS_HOOK_DIR:-$(cd "$(dirname "$0")" && pwd)}"
	unset QS_HOOK_DIR
	[ -f "${HOOK_DIR}/quality-suite.env" ] || return 0
	[ "$export_all" = 1 ] && set -a
	# why: the sourced path is only known at run time
	# shellcheck disable=SC1090,SC1091
	. "${HOOK_DIR}/quality-suite.env"
	[ "$export_all" = 1 ] && set +a
	return 0
}

# qs_hook_flow_lib [--no-docker]: source git-flow-lib.sh, check the suite stamp, load the policy.
# Arguments: --no-docker sets QS_POLICY_NO_DOCKER=1 for the policy load (post-commit does).
# Sets LIB. Return value: 0 when loaded; 1 when the library is missing (old suite), so the hook
# keeps its own fallback (exit 0 or defaults).
qs_hook_flow_lib() {
	LIB="${QUALITY_SUITE_DIR:-}/scripts/git-flow-lib.sh"
	[ -f "$LIB" ] || return 1
	# why: the sourced path is only known at run time
	# shellcheck disable=SC1090
	. "$LIB"
	qs_suite_stamp_check
	if [ "${1:-}" = --no-docker ]; then
		QS_POLICY_NO_DOCKER=1 qs_policy_load
	else
		qs_policy_load
	fi
}

# qs_hook_docker_lib: check that the suite is installed, then load the shared docker helpers.
# Arguments: none (reads QUALITY_SUITE_DIR, set by quality-suite.env or the hook environment).
# Sets the helper functions and QS_* variables of scripts/qs-docker-lib.sh.
# Return value: 0 when loaded. Errors: when QUALITY_SUITE_DIR is empty, prints
# "QUALITY_SUITE_DIR not set" to stderr and exits the calling hook with status 1.
qs_hook_docker_lib() {
	[ -n "${QUALITY_SUITE_DIR:-}" ] || {
		echo "[quality-suite] QUALITY_SUITE_DIR not set (run install.sh)." >&2
		exit 1
	}
	# why: the sourced path is only known at run time
	# shellcheck disable=SC1091
	. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
}
