#!/usr/bin/env bash
# qs-alias: checkpoint
# git-checkpoint.sh (git alias: git checkpoint) - local save points of a task, on the special branch
# '<node>/CHECKPOINT-<task>'.
#   git checkpoint "<message>"   save the work tree (tracked and untracked files, not ignored ones)
#       as one more commit of CHECKPOINT-<task>, created from the task tip the first time. The
#       commit is made with plumbing (temporary index, commit-tree, update-ref): no hook runs and
#       the current branch, its index and the work tree do not change.
#   git checkpoint --lista       the numbered points (1 = the oldest) with id, date and message.
#   git checkpoint --volver <n> [--force]
#       make the work tree equal to point <n>; the branch and its commits do not move (the index is
#       left as HEAD, so the differences show as changes). Refused on a dirty tree unless --force.
# A CHECKPOINT branch is local: it is never pushed (the special table says push never) and it is
# deleted when its task is integrated.

# shellcheck disable=SC1091
if ! declare -F is_testing_branch >/dev/null 2>&1; then
	. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-flow-lib.sh"
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

CK_PREFIX="chore(checkpoint): "

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
ck_die() {
	echo "[checkpoint] $*" >&2
	exit 1
}

# The CHECKPOINT branch of the current task branch. An attempt '<node>/<task>/ATTEMPT-<n>' has the
# checkpoints of its task, so it maps through '<node>/<task>'.
# Arguments: $1 current branch. Returns: 0 and prints '<node>/CHECKPOINT-<task>'; exits 1 with the
# reason when the branch is not a task (mainline, other special or invalid name).
ck_branch_of() {
	local cur="$1" node task why
	why="$(valid_branch_name "$cur" 2>&1)" || ck_die "'$cur' is not a valid branch: $why"
	is_mainline "$cur" && ck_die "'$cur' is not a task branch"
	# why: the attempt segment is the leaf; its task is the segment before it
	if [[ ${cur##*/} =~ ^ATTEMPT-[0-9]+$ ]] && [ "$(special_kind "$cur")" = ATTEMPT ]; then
		ck_branch_of "${cur%/*}"
		return
	fi
	[ -z "$(special_kind "$cur")" ] || ck_die "'$cur' is a special branch: checkpoint a task branch"
	node="${cur%/"$QS_BR_LEAF"}"
	[ "$(branch_depth "$node")" -ge 3 ] || ck_die "'$cur' is not a task branch"
	task="${node##*/}"
	printf '%s/CHECKPOINT-%s' "${node%/*}" "$task"
}

# The commits (oldest first) that are save points of a CHECKPOINT branch: the first-parent chain
# of its tip made of checkpoint commits.
# Arguments: $1 branch. Returns: 0 and prints one commit id per line (nothing when none).
ck_points() {
	local c list=""
	git show-ref --verify -q "refs/heads/$1" || return 0
	for c in $(git rev-list --first-parent "refs/heads/$1"); do
		case "$(git log -1 --format=%s "$c")" in "$CK_PREFIX"*) list="$c $list" ;; *) break ;; esac
	done
	for c in $list; do echo "$c"; done
}

# Save the work tree as a new point.
# Arguments: $1 message. Returns: 0 and prints the point number; exits 1 on an empty message or
# when a git step fails.
cmd_save() {
	local msg="$1" cur ck idx tree parent c n gd
	[ -n "$msg" ] || ck_die 'usage: git checkpoint "<message>"'
	cur="$(current_branch)" || ck_die "detached HEAD"
	ck="$(ck_branch_of "$cur")"
	gd="$(git rev-parse --absolute-git-dir)"
	idx="$gd/checkpoint.idx"
	# why: a copy of the index is filled with the work tree, so the real index is never touched
	cp "$(git rev-parse --git-path index)" "$idx" 2>/dev/null || rm -f "$idx"
	if ! GIT_INDEX_FILE="$idx" git add -A -- "$(git rev-parse --show-toplevel)" ||
		! tree="$(GIT_INDEX_FILE="$idx" git write-tree)"; then
		rm -f "$idx"
		ck_die "cannot snapshot the work tree"
	fi
	rm -f "$idx"
	if git show-ref --verify -q "refs/heads/$ck"; then
		parent="$(git rev-parse "refs/heads/$ck")"
	else
		parent="$(git rev-parse "refs/heads/$cur")"
	fi
	c="$(git commit-tree "$tree" -p "$parent" -m "$CK_PREFIX$msg")" || ck_die "cannot create the commit"
	git update-ref "refs/heads/$ck" "$c" || ck_die "cannot update $ck"
	n="$(ck_points "$ck" | wc -l | tr -d ' ')"
	echo "[checkpoint] point $n saved on $ck: $msg"
}

# Print the numbered points of the current task.
# Arguments: none. Returns: 0; exits 1 when the branch is not a task.
cmd_lista() {
	local cur ck c subj n=0
	cur="$(current_branch)" || ck_die "detached HEAD"
	ck="$(ck_branch_of "$cur")"
	for c in $(ck_points "$ck"); do
		n=$((n + 1))
		subj="$(git log -1 --format=%s "$c")"
		printf '%d  %s  %s  %s\n' "$n" "$(git log -1 --format=%h "$c")" \
			"$(git log -1 --format=%ad --date=format:'%Y-%m-%d %H:%M' "$c")" "${subj#"$CK_PREFIX"}"
	done
	[ "$n" -gt 0 ] || echo "[checkpoint] no points on $ck"
}

# Make the work tree equal to a point.
# Arguments: $1 point number, $2 'force' to discard a dirty tree. Returns: 0; exits 1 for an unknown
# point or a dirty tree without force.
cmd_volver() {
	local n="$1" force="$2" cur ck sha f
	case "$n" in '' | *[!0-9]*) ck_die "usage: git checkpoint --volver <n> [--force]" ;; esac
	cur="$(current_branch)" || ck_die "detached HEAD"
	ck="$(ck_branch_of "$cur")"
	sha="$(ck_points "$ck" | sed -n "${n}p")"
	[ -n "$sha" ] || ck_die "no point $n on $ck (git checkpoint --lista)"
	if [ "$force" != force ] && [ -n "$(git status --porcelain)" ]; then
		ck_die "the work tree is not clean: commit, or use --force to discard it"
	fi
	# why: files that exist now but not in the point must go; the rest is restored from the point
	while IFS= read -r f; do
		git cat-file -e "$sha:$f" 2>/dev/null || rm -f -- "$f"
	done < <(git ls-files -c -o --exclude-standard)
	git checkout -q "$sha" -- . || ck_die "cannot restore point $n"
	git reset -q
	echo "[checkpoint] work tree equal to point $n of $ck"
}

# Entry point of the git alias.
# Arguments: the command line after 'git checkpoint'. Returns: the exit status of the command.
ck_main() {
	local cmd="${1:-}" force=""
	qs_policy_load
	special_enabled CHECKPOINT || ck_die "CHECKPOINT is disabled (needs branches.flow: squash and the CHECKPOINT type)"
	case "$cmd" in
	--lista | lista) cmd_lista ;;
	--volver | volver)
		shift
		[ "${2:-}" != --force ] || force=force
		cmd_volver "${1:-}" "$force"
		;;
	-h | --help | '')
		awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"
		[ -n "$cmd" ] || exit 2
		;;
	*) cmd_save "$cmd" ;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ck_main "$@"; fi
