#!/usr/bin/env bash
# git-revision.sh (git alias: git revision) - the REVIEW branch of a task, 6.0.0 special branch.
# qs-alias: revision
#   git revision <task>
#       creates '<node>/REVIEW-<leaf>' at the tip of the task branch <task> (the node is its folder).
#       A reviewer (or qa) commits proposals there; the task branch is never touched.
#   git revision --aplicar [<commit>...] [<task>]
#       run from the task branch (or give it): 'cherry-pick -x' onto the task the chosen proposals
#       (commits of REVIEW-<leaf> not in the task), or all of them, oldest first. A conflict aborts
#       the cherry-pick and leaves the task as it was.
#   git revision --descartar [<task>]
#       deletes REVIEW-<leaf>, local and origin.
# REVIEW is never integrated or merged (git integra and the hooks refuse it); 'git subir' rebases
# it onto the task and integrating the task deletes it.

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-flow-lib.sh"
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
rv_die() {
	echo "[revision] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
rv_say() { echo "[revision] $*"; }

# Name of the REVIEW branch of a task: '<folder>/REVIEW-<leaf>'.
# Arguments: $1 task branch. Returns: 0; prints the name.
rv_name() {
	local pre=""
	case "$1" in */*) pre="${1%/*}/" ;; esac
	printf '%sREVIEW-%s' "$pre" "${1##*/}"
}

# The task branch: the given one, or the current one (its REVIEW branch counts as its task).
# Arguments: $1 explicit branch (may be empty). Returns: 0 and prints the task; exits 1 when there
# is none, it does not exist, or it is not a final task branch.
rv_task() {
	local t="$1" cur leaf
	if [ -z "$t" ]; then
		cur="$(current_branch)" || rv_die "no task given and HEAD is detached"
		leaf="${cur##*/}"
		case "$leaf" in
		REVIEW-?*) t="${cur%/*}/${leaf#REVIEW-}" ;;
		*) t="$cur" ;;
		esac
	fi
	[ "$(special_kind "$t")" = "" ] || rv_die "'$t' is a special branch: REVIEW goes with an ordinary task"
	is_parent_branch "$t" && rv_die "'$t' is an ORIGINAL: REVIEW goes with a final task branch"
	is_mainline "$t" && rv_die "'$t' is a mainline branch"
	best_ref "$t" >/dev/null || rv_die "no such branch: $t"
	printf '%s' "$t"
}

# Whether a local or origin branch exists.
# Arguments: $1 branch. Returns: 0 when it does; 1 otherwise.
rv_exists() { best_ref "$1" >/dev/null 2>&1; }

# Create REVIEW-<task> at the tip of the task and switch to it when possible.
# Arguments: $1 task. Returns: 0; exits 1 when REVIEW is off or already exists.
rv_create() {
	local t="$1" r tip
	special_enabled REVIEW || rv_die "REVIEW branches are off (branches.special) or the flow is not squash"
	r="$(rv_name "$t")"
	valid_branch_name "$r" >/dev/null 2>&1 || rv_die "'$r' is not a valid branch name here"
	rv_exists "$r" && rv_die "$r already exists (git revision --descartar $t, to start again)"
	tip="$(best_ref "$t")"
	git branch --no-track "$r" "$tip"
	rv_say "created $r at $tip"
	# why: a branch checked out in another worktree cannot be switched to; the branch is still made
	command -v qs_publish_new >/dev/null && qs_publish_new "$r"
	git switch -q "$r" 2>/dev/null || rv_say "stay on $(current_branch || echo HEAD); switch to $r to commit proposals"
	return 0
}

# Proposals of a REVIEW branch: its commits whose change the task does not have yet (git cherry,
# by patch id), oldest first.
# Arguments: $1 task. Returns: 0; prints one full sha per line; exits 1 without REVIEW.
rv_proposals() {
	local t="$1" r rr
	r="$(rv_name "$t")"
	rr="$(best_ref "$r")" || rv_die "$r does not exist (git revision $t)"
	git cherry "$(best_ref "$t")" "$rr" | awk '$1 == "+" { print $2 }'
}

# Cherry-pick proposals onto the task, which must be the current branch.
# Arguments: $1 task, $@ commits (may be none: all proposals). Returns: 0; exits 1 when a commit is
# not a proposal, the task is not checked out, or a cherry-pick fails (then it is aborted).
rv_apply() {
	local t="$1" c sha all picks=()
	shift
	[ "$(current_branch || true)" = "$t" ] || rv_die "check out $t first: --aplicar commits onto it"
	all="$(rv_proposals "$t")"
	[ -n "$all" ] || rv_die "$(rv_name "$t") has no proposals"
	if [ "$#" -eq 0 ]; then
		while IFS= read -r sha; do picks+=("$sha"); done <<<"$all"
	else
		for c in "$@"; do
			sha="$(git rev-parse -q --verify "$c^{commit}")" || rv_die "unknown commit: $c"
			grep -qxF "$sha" <<<"$all" || rv_die "$c is not a pending proposal of $(rv_name "$t")"
			picks+=("$sha")
		done
		# why: keep the order of the proposals, not the order typed
		local ordered=()
		while IFS= read -r sha; do
			for c in "${picks[@]}"; do [ "$c" = "$sha" ] && ordered+=("$sha"); done
		done <<<"$all"
		picks=("${ordered[@]}")
	fi
	for sha in "${picks[@]}"; do
		if ! git cherry-pick -x "$sha" >/dev/null; then
			git cherry-pick --abort 2>/dev/null || true
			rv_die "cherry-pick of $sha failed; $t is as it was before this commit"
		fi
		rv_say "applied $(git log -n1 --format='%h %s' "$sha")"
	done
}

# Delete REVIEW-<task>, local and origin (leaves it first when it is checked out).
# Arguments: $1 task. Returns: 0; exits 1 when there is no such branch.
rv_discard() {
	local t="$1" r
	r="$(rv_name "$t")"
	rv_exists "$r" || rv_die "$r does not exist"
	if [ "$(current_branch || true)" = "$r" ]; then git switch -q "$t" || rv_die "cannot leave $r"; fi
	if git rev-parse -q --verify "refs/heads/$r" >/dev/null; then
		rv_say "tip of $r was $(git rev-parse --short "refs/heads/$r") (git branch $r <sha> restores it)"
		git branch -D "$r" >/dev/null
	fi
	if git rev-parse -q --verify "refs/remotes/origin/$r" >/dev/null; then
		git push -q origin --delete "$r" 2>/dev/null || rv_say "WARN: could not delete $r on origin"
		git update-ref -d "refs/remotes/origin/$r" 2>/dev/null || true
	fi
	rv_say "deleted $r"
}

# Entry point: dispatch on the first argument.
# Arguments: see the header. Returns: 0; exits 1 on a refusal.
rv_main() {
	local mode=create args=() a
	qs_policy_load
	for a in "$@"; do
		case "$a" in
		--aplicar) mode=apply ;;
		--descartar) mode=discard ;;
		-h | --help)
			sed -n '2,15p' "${BASH_SOURCE[0]}"
			return 0
			;;
		-*) rv_die "unknown option $a" ;;
		*) args+=("$a") ;;
		esac
	done
	case "$mode" in
	create)
		[ "${#args[@]}" -eq 1 ] || rv_die "usage: git revision <task> | --aplicar [commit...] | --descartar [task]"
		rv_create "$(rv_task "${args[0]}")"
		;;
	discard)
		[ "${#args[@]}" -le 1 ] || rv_die "usage: git revision --descartar [task]"
		rv_discard "$(rv_task "${args[0]:-}")"
		;;
	apply)
		# why: a commit id has no '/', a task branch always has one
		local t="" commits=()
		for a in "${args[@]}"; do
			if [ -z "$t" ] && [[ $a == */* ]] && rv_exists "$a"; then t="$a"; else commits+=("$a"); fi
		done
		t="$(rv_task "$t")"
		rv_apply "$t" "${commits[@]}"
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then rv_main "$@"; fi
