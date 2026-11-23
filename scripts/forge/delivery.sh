#!/usr/bin/env bash
# delivery.sh - resolve branches.delivery (auto | pr | push) for a target branch.
# Sourced by the publish commands; never run directly. Until the policy key exists the mode
# comes from QS_BR_DELIVERY (default auto). Detection is read-only: at most GET calls.

_QS_DELIVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/forge/forge-lib.sh
. "$_QS_DELIVERY_DIR/forge-lib.sh"

# Answer for a mode when the provider cannot be used. Arguments: mode reason. Output: for auto
# the push answer with the notice line (returns 0); for pr the fix on stderr (returns 1).
_qs_delivery_fallback() {
	if [ "$1" = pr ]; then
		forge_say "branches.delivery is pr but $2: fix it (gh auth login; a GitHub origin) or set branches.delivery to push"
		return 1
	fi
	printf 'push\n[publicar] delivery auto: %s; pushing directly (set branches.delivery to pr or push)\n' "$2"
}

# Decide how a release lands on a branch. Arguments: branch (the target, e.g. develop).
# Output: two lines on stdout, "pr" or "push", then one reason line (for "auto" falling back
# to push it is the full "[publicar] delivery auto: <reason>; pushing directly (...)" line).
# Returns: 0 resolved; 1 refused, with the fix on stderr and nothing on stdout (invalid mode,
# "pr" without a provider, gh or login, or a token that comes from a tracked file).
qs_delivery_resolve() {
	local branch="${1:?branch}" mode="${QS_BR_DELIVERY:-auto}" why="" rc
	case "$mode" in
	push)
		printf 'push\nbranches.delivery is push\n'
		return 0
		;;
	pr | auto) ;;
	*)
		forge_say "invalid branches.delivery '$mode': use auto, pr or push"
		return 1
		;;
	esac
	if ! forge_load "${QS_FORGE_REMOTE:-origin}"; then
		why="origin host has no forge provider"
	elif ! forge_have_cli; then
		why="gh is not installed"
	elif ! forge_logged_in; then
		why="gh is not logged in"
	fi
	if [ -n "$why" ]; then
		_qs_delivery_fallback "$mode" "$why"
		return
	fi
	forge_check_token || return 1
	if [ "$mode" = pr ]; then
		printf 'pr\nbranches.delivery is pr\n'
		return 0
	fi
	rc=0
	forge_requires_pr "$branch" || rc=$?
	case "$rc" in
	0) printf 'pr\ndelivery auto: %s requires a pull request\n' "$branch" ;;
	1) printf 'push\ndelivery auto: %s has no pull request rule\n' "$branch" ;;
	*) _qs_delivery_fallback "$mode" "the pull request rule of $branch could not be read" ;;
	esac
}
