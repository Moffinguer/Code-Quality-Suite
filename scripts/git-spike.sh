#!/usr/bin/env bash
# git-spike.sh - the SPIKE special branch (6.0.0): throw-away exploration that never goes up.
# qs-alias: spike
#   git spike
#       On an ORIGINAL (an OT or deeper) creates '<node>/SPIKE' at that ORIGINAL and checks it out.
#       One SPIKE per node. A SPIKE is never integrated or merged into its node (git integra and
#       the hooks refuse it); 'git convertir-padre' makes it '<node>/SPIKE/ORIGINAL' for children.
#   git spike --llevar <branch> <task>
#       Takes the own commits of a SPIKE branch ('<node>/SPIKE', or one inside '<node>/SPIKE/')
#       out to a new final branch '<node>/<task>' created at '<node>/ORIGINAL'. Each commit keeps
#       its author and message and gains the trailer 'Spike-of: <branch> <sha>'. The work is done
#       with plumbing (no hook runs, no work tree or checkout changes): a conflict stops with
#       instructions and leaves no branch behind.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/git-flow-lib.sh
. "$DIR/git-flow-lib.sh"
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
sp_die() {
	echo "[spike] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
sp_say() { echo "[spike] $*"; }

# Whether a branch exists locally, on origin, or as a folder of branches.
# Arguments: $1 branch. Returns: 0 when taken; 1 when free.
sp_taken() {
	git show-ref --verify -q "refs/heads/$1" || git show-ref --verify -q "refs/remotes/origin/$1" ||
		[ -n "$(git for-each-ref --count=1 "refs/heads/$1/" "refs/remotes/origin/$1/")" ]
}

# Fetch origin quietly when there is one.
# Arguments: none. Returns: 0 always (an offline fetch is not an error).
sp_fetch() {
	if git remote get-url origin >/dev/null 2>&1; then git fetch -q --prune origin 2>/dev/null || true; fi
	return 0
}

# Publish new branches through qs_publish_new when the autopublish task provides it (guarded:
# without it the branches stay local and 'git subir' publishes them).
# Arguments: $@ branches. Returns: 0 always.
sp_publish() {
	if command -v qs_publish_new >/dev/null 2>&1; then qs_publish_new "$@" || true; fi
	return 0
}

# Common checks of both commands: the SPIKE type is on and the version is not locked.
# Arguments: $1 the branch about to be created. Returns: 0; exits 1 with the reason otherwise.
sp_precheck() {
	local why
	special_enabled SPIKE || sp_die "SPIKE is disabled or the flow is not squash (branches.special.SPIKE)"
	sp_fetch
	why="$(special_migration_lock "${1%%/*}" "$1")" && sp_die "$why"
	return 0
}

# git spike: create '<node>/SPIKE' from the current ORIGINAL.
# Arguments: none. Returns: 0 on success; exits 1 when not on an ORIGINAL of a node, when the
# name is not valid there (version level), or when the node already has a SPIKE.
cmd_spike() {
	local cur node new base why
	cur="$(current_branch)" || sp_die "detached HEAD: check out an ORIGINAL branch first"
	is_parent_branch "$cur" || sp_die "'$cur' is not an ORIGINAL branch: run git spike on the ORIGINAL of the node"
	node="$(branch_node "$cur")"
	new="$node/SPIKE"
	why="$(valid_branch_name "$new")" || sp_die "no SPIKE here: $why"
	sp_precheck "$new"
	sp_taken "$new" && sp_die "$node already has a SPIKE ($new): one per node"
	base="$(best_ref "$cur" || true)"
	git branch -q --no-track "$new" "${base:-$cur}"
	git checkout -q "$new"
	sp_say "created '$new' from '${base:-$cur}'; it never goes up (git spike --llevar takes commits out)"
	sp_publish "$new"
	return 0
}

# Decide the node and the base ref of a spike branch.
# Arguments: $1 spike branch. Returns: 0 and sets SP_NODE (the node) and SP_BASE (the ref its
# own commits start from: its parent, so a branch inside SPIKE/ does not carry its parent's work);
# exits 1 when the branch is not a SPIKE branch or does not exist.
sp_locate() {
	local b="$1" par
	[ "$(special_kind "$b")" = SPIKE ] || sp_die "'$b' is not a SPIKE branch ('<node>/SPIKE' or inside '<node>/SPIKE/')"
	SP_NODE="${b%%/SPIKE*}"
	SP_REF="$(best_ref "$b" || true)"
	[ -n "$SP_REF" ] || sp_die "branch '$b' does not exist"
	par="$(parent_branch "$b")"
	SP_BASE="$(best_ref "$par" || true)"
	[ -n "$SP_BASE" ] || sp_die "the parent '$par' of '$b' does not exist"
	return 0
}

# Replay the commits of a range on a base with plumbing, adding the Spike-of trailer.
# Arguments: $1 spike branch name, $2 base commit, $3.. the commits, oldest first. Returns: 0 and
# prints the new tip; 1 (message on stderr, nothing created) when a commit conflicts. A commit that
# changes nothing on top of the base is skipped.
sp_replay() {
	local b="$1" acc="$2" c out tree msg new
	shift 2
	for c in "$@"; do
		if ! out="$(git merge-tree --write-tree --merge-base="$c^" "$acc" "$c" 2>&1)"; then
			echo "[spike] conflict taking $(git log -n1 --format='%h %s' "$c") from '$b': nothing was created." >&2
			echo "[spike] Make the commit independent of the rest of the spike (or cherry-pick by hand:" >&2
			echo "        git switch -c <branch> <node>/ORIGINAL && git cherry-pick -x $c)." >&2
			return 1
		fi
		tree="$(head -n1 <<<"$out")"
		[ "$tree" != "$(git rev-parse "$acc^{tree}")" ] || continue
		msg="$(git log -n1 --format=%B "$c" | git interpret-trailers --trailer "Spike-of: $b $c")"
		new="$(GIT_AUTHOR_NAME="$(git log -n1 --format=%an "$c")" GIT_AUTHOR_EMAIL="$(git log -n1 --format=%ae "$c")" \
		GIT_AUTHOR_DATE="$(git log -n1 --format=%aI "$c")" git commit-tree "$tree" -p "$acc" -m "$msg")"
		acc="$new"
	done
	printf '%s' "$acc"
}

# git spike --llevar <branch> <task>: take the own commits of a SPIKE branch to '<node>/<task>'.
# Arguments: $1 spike branch, $2 task name. Returns: 0 on success; exits 1 when the branch is not
# a SPIKE branch, has no commits of its own, the task name is invalid or taken, or a commit
# conflicts (no branch is left behind).
cmd_llevar() {
	local b="${1:-}" task="${2:-}" new orig_ref tip commits=() c why
	if [ -z "$b" ] || [ -z "$task" ]; then sp_die "usage: git spike --llevar <spike-branch> <task>"; fi
	sp_locate "$b"
	case "$task" in */* | "") sp_die "the task name is one segment (no '/'): $task" ;; esac
	special_refusal "$task" >/dev/null && sp_die "$(special_refusal "$task")"
	new="$SP_NODE/$task"
	why="$(valid_branch_name "$new")" || sp_die "invalid name '$new': $why"
	sp_precheck "$new"
	sp_taken "$new" && sp_die "'$new' already exists"
	orig_ref="$(best_ref "$SP_NODE/$QS_BR_LEAF" || true)"
	[ -n "$orig_ref" ] || sp_die "'$SP_NODE/$QS_BR_LEAF' does not exist"
	while IFS= read -r c; do
		[ -n "$c" ] && commits+=("$c")
	done < <(git rev-list --no-merges --reverse "$SP_BASE..$SP_REF")
	[ "${#commits[@]}" -gt 0 ] || sp_die "'$b' has no commits of its own to take"
	tip="$(sp_replay "$b" "$(git rev-parse "$orig_ref^{commit}")" "${commits[@]}")" || exit 1
	git branch -q --no-track "$new" "$tip"
	sp_say "created '$new' from '$orig_ref' with ${#commits[@]} commit(s) of '$b' (Spike-of: trailers); check it out and review"
	sp_publish "$new"
	return 0
}

# Entry point.
# Arguments: the command line. Returns: 0 on success; exits 1 on any error.
main() {
	qs_policy_load
	case "${1:-}" in
	"") cmd_spike ;;
	--llevar)
		shift
		cmd_llevar "$@"
		;;
	-h | --help) sed -n '2,13p' "${BASH_SOURCE[0]}" ;;
	*) sp_die "usage: git spike | git spike --llevar <spike-branch> <task>" ;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
