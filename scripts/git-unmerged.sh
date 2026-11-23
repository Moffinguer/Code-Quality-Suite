#!/usr/bin/env bash
# git-unmerged.sh (alias: git limpiar-unmerged) - delete the archived branches ('unmerged/...',
# 'unmerged-<stamp>/...') whose work already reached the mainline, locally and on origin.
#   git limpiar-unmerged [-n] [--yes]
#   -n     preview: print the state of every branch and the plan; nothing is fetched or changed
#   --yes  do not ask for confirmation
# Test-only: QS_UNMERGED_PAUSE_CMD is run with bash -c between the fetch and the confirmation, and
# only when QS_TEST=1 is also set; otherwise it is ignored silently (never use it outside the suite).
# The mainline is judged as origin/develop when origin has it (local develop must be contained in
# it); without origin the local develop is used and the output says so.
# States: integrated (a simulated merge with the mainline changes nothing but release files),
# superseded by <ref> (proved: ancestor of, or same content as, an integrated archived branch or a
# release tag), pending (anything else; never deleted).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/git-flow-lib.sh
. "$DIR/git-flow-lib.sh"

DRY=0
YES=0
MAIN_REF=""
declare -A STATE REASON TIPS LOCAL_TIP REMOTE_TIP
INTEGRATED=()

# die MESSAGE...: print the message to stderr and exit 1.
die() {
	echo "[unmerged] $*" >&2
	exit 1
}

# say MESSAGE...: print a tagged message to stdout.
say() { echo "[unmerged] $*"; }

# strip_release_lines FILE REF: filter stdin removing the release lines of FILE as found in REF:
# the README version badge, the project's own <version> in pom.xml (and the <parent> version when
# the parent lives in this repository) and the top-level "version" of package.json. Dependency,
# plugin and external parent versions are never removed: a false "pending" is safe.
strip_release_lines() {
	case "$1" in
	"$QS_BR_README") sed -e 's|<!-- qs:version -->.*<!-- /qs:version -->||' | grep -v '^[[:space:]]*$' || true ;;
	*pom.xml) awk -v mode=strip -v ours="$(pom_artifacts "$2")" "$POM_AWK" ;;
	*package.json) awk "$JSON_AWK" ;;
	*) cat ;;
	esac
}

# real_changes A B: print "<status> <file>" for every file that differs between the commits A and B,
# leaving out release files and release lines. Empty output means the same content. Returns 0.
real_changes() {
	local st f
	while IFS=$'\t' read -r st f; do
		[ -n "$f" ] || continue
		release_owned_file "$f" && continue
		case "$f" in
		"$QS_BR_README" | *pom.xml | *package.json)
			if [ "$st" = M ] && cmp -s <(git show "$1:$f" 2>/dev/null | strip_release_lines "$f" "$1") \
				<(git show "$2:$f" 2>/dev/null | strip_release_lines "$f" "$2"); then
				continue
			fi
			;;
		esac
		echo "${st:0:1} $f"
	done < <(git diff --name-status "$1" "$2")
}

# check_integrated TIP: simulate merging TIP into the mainline. Prints nothing and returns 0 when
# only release files would change; otherwise prints one "M <file>" line per real change (or a
# line starting with '!' giving the reason) and returns 1.
check_integrated() {
	local tip="$1" fork t out
	fork="$(git merge-base "$tip" "$MAIN_REF" 2>/dev/null)" || {
		echo "! no merge base with $MAIN_REF"
		return 1
	}
	out="$(git merge-tree --write-tree --merge-base "$fork" "$MAIN_REF" "$tip" 2>/dev/null)" || {
		echo "! merge with $MAIN_REF conflicts"
		return 1
	}
	t="$(head -1 <<<"$out")"
	out="$(real_changes "$MAIN_REF" "$t")"
	[ -z "$out" ] && return 0
	echo "$out"
	return 1
}

# find_superseder TIP: print the proof that TIP is superseded (an integrated archived branch of
# which TIP is an ancestor or with the same content, or a release tag with the same content) and
# return 0; return 1 when there is no proof.
find_superseder() {
	local tip="$1" b o tag
	for b in "${INTEGRATED[@]}"; do
		for o in ${TIPS[$b]}; do
			[ "$o" = "$tip" ] && continue
			if git merge-base --is-ancestor "$tip" "$o" 2>/dev/null ||
				[ -z "$(real_changes "$tip" "$o")" ]; then
				echo "$b"
				return 0
			fi
		done
	done
	while IFS= read -r tag; do
		[ -n "$tag" ] || continue
		if [ -z "$(real_changes "$tip" "$tag^{commit}")" ]; then
			echo "$tag"
			return 0
		fi
	done < <(git tag --list '[0-9]*' 'v[0-9]*')
	return 1
}

# archived_names: print the short name of every archived branch, local or on origin, one per line.
archived_names() {
	{
		git for-each-ref --format='%(refname:short)' refs/heads
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin
	} | { grep -E "^${QS_BR_ARCHIVE}(-[^/]*)?/." || true; } | sort -u
}

# push_deletions NAME...: delete the origin branches in one atomic push, each with a lease on the
# tip seen. Returns the push status.
push_deletions() {
	local args=(--atomic) n
	for n in "$@"; do
		args+=("--force-with-lease=refs/heads/$n:${REMOTE_TIP[$n]}")
	done
	args+=(origin)
	for n in "$@"; do args+=(":refs/heads/$n"); done
	git push -q "${args[@]}"
}

# classify NAME...: set STATE/REASON of each archived branch (integrated, "superseded by <ref>" or
# pending). A branch whose local and origin tips differ is judged on both and is pending if either is.
classify() {
	local n a out why
	for n in "$@"; do
		STATE[$n]=integrated
		REASON[$n]=""
		for a in ${TIPS[$n]}; do
			if out="$(check_integrated "$a")"; then continue; fi
			STATE[$n]=pending
			REASON[$n]+="$out"$'\n'
		done
		[ "${STATE[$n]}" = integrated ] && INTEGRATED+=("$n")
	done
	for n in "$@"; do
		[ "${STATE[$n]}" = pending ] || continue
		[ "$(wc -w <<<"${TIPS[$n]}")" -eq 1 ] || continue
		if why="$(find_superseder "${TIPS[$n]% }")"; then
			STATE[$n]="superseded by $why"
		fi
	done
}

# delete_branches NAME...: remove the branches locally (all but those checked out in a worktree),
# printing "deleted <branch> (was <sha>)" for each. Origin was already handled by the caller.
delete_branches() {
	local n own sha
	own="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"
	for n in "$@"; do
		sha="${LOCAL_TIP[$n]:-${REMOTE_TIP[$n]}}"
		if [ -n "${LOCAL_TIP[$n]}" ] && grep -qxF "$n" <<<"$own"; then
			say "kept local $n (checked out in a worktree)${REMOTE_TIP[$n]:+; origin copy deleted (was ${REMOTE_TIP[$n]})}"
			continue
		fi
		[ -z "${LOCAL_TIP[$n]}" ] || git update-ref -d "refs/heads/$n"
		git update-ref -d "refs/remotes/origin/$n" 2>/dev/null || true
		say "deleted $n (was $sha)"
	done
}

# main [-n] [--yes]: classify the archived branches, print the plan and delete the integrated and
# superseded ones. Exit: 0 done or nothing to do; 1 error or origin push rejected.
main() {
	local n l r a ans names=() deletable=() remote=() has_origin=0
	while [ $# -gt 0 ]; do
		case "$1" in
		-n) DRY=1 ;;
		--yes) YES=1 ;;
		-h | --help)
			sed -n '2,13p' "${BASH_SOURCE[0]}"
			return 0
			;;
		*) die "unknown argument '$1' (usage: git limpiar-unmerged [-n] [--yes])" ;;
		esac
		shift
	done
	git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
	qs_policy_load
	qs_ref_exists "refs/heads/$QS_BR_MAINLINE" || die "no local branch $QS_BR_MAINLINE"
	git remote | grep -qx origin && has_origin=1
	if [ "$has_origin" = 1 ] && [ "$DRY" = 0 ]; then
		git fetch -q --prune origin || die "fetch from origin failed"
		# why: test-only hook (see the header) so a test can move origin between fetch and push;
		# QS_TEST=1 is required so a stray variable in a user's environment cannot run code here
		if [ "${QS_TEST:-0}" = 1 ] && [ -n "${QS_UNMERGED_PAUSE_CMD:-}" ]; then
			bash -c "$QS_UNMERGED_PAUSE_CMD" </dev/null || die "QS_UNMERGED_PAUSE_CMD failed"
		fi
	fi
	MAIN_REF="$QS_BR_MAINLINE"
	if [ "$has_origin" = 1 ] && qs_ref_exists "refs/remotes/origin/$QS_BR_MAINLINE"; then
		git merge-base --is-ancestor "$QS_BR_MAINLINE" "origin/$QS_BR_MAINLINE" ||
			die "local $QS_BR_MAINLINE is not contained in origin/$QS_BR_MAINLINE (push or sync it first): a local-only merge does not prove integration"
		MAIN_REF="origin/$QS_BR_MAINLINE"
		say "judging against $MAIN_REF"
	else
		say "no origin/$QS_BR_MAINLINE: judging against the local $QS_BR_MAINLINE only"
	fi
	mapfile -t names < <(archived_names)
	if [ "${#names[@]}" -eq 0 ]; then
		say "nothing to clean"
		return 0
	fi
	for n in "${names[@]}"; do
		l="$(git rev-parse -q --verify "refs/heads/$n" 2>/dev/null || true)"
		r="$(git rev-parse -q --verify "refs/remotes/origin/$n" 2>/dev/null || true)"
		LOCAL_TIP[$n]="$l"
		REMOTE_TIP[$n]="$r"
		TIPS[$n]="$(printf '%s\n' "$l" "$r" | grep . | sort -u | tr '\n' ' ')"
	done
	classify "${names[@]}"
	for n in "${names[@]}"; do
		echo "${STATE[$n]}: $n"
		if [ "${STATE[$n]}" = pending ]; then
			while IFS= read -r a; do
				[ -n "$a" ] || continue
				echo "    ${a#! }"
			done <<<"${REASON[$n]}"
		else
			deletable+=("$n")
		fi
	done
	if [ "${#deletable[@]}" -eq 0 ]; then
		say "nothing to delete: every archived branch is pending"
		return 0
	fi
	say "plan: delete ${#deletable[@]} branch(es), locally and on origin; pending ones are kept"
	if [ "$DRY" = 1 ]; then
		say "preview only (-n): nothing fetched, nothing changed"
		return 0
	fi
	if [ "$YES" = 0 ]; then
		printf '[unmerged] Delete them? [y/N] '
		ans=""
		read -r ans || true
		case "$ans" in y | Y | yes | YES) ;; *)
			say "cancelled; nothing was deleted"
			return 0
			;;
		esac
	fi
	# why: origin first, in one atomic push with leases; a rejection stops before any local change
	for n in "${deletable[@]}"; do
		[ -z "${REMOTE_TIP[$n]}" ] || remote+=("$n")
	done
	if [ "${#remote[@]}" -gt 0 ]; then
		push_deletions "${remote[@]}" || die "the atomic push was rejected (a branch moved on origin?); nothing was deleted. Run it again"
	fi
	delete_branches "${deletable[@]}"
	return 0
}

main "$@"
