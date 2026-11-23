#!/usr/bin/env bash
# qs-alias: bug-conocido
# git-bug.sh (git alias: git bug-conocido) - a bug found in a released version is documented first.
#   git bug-conocido [-n] "<where>" "<symptom>"
#       1. On the current branch (a final or special branch, clean tree) adds a row to KNOWN_BUGS.md
#          and commits it: 'docs(bugs): <where>', one file, trailer 'Known-bug: <date> <where>'.
#       2. Cherry-picks that commit (-x line in the message) onto every other branch of the project:
#          develop, every ORIGINAL and every final (never main, RELEASE, archived, TESTING or
#          SPIKE branches). The copies are made with plumbing (merge-tree, commit-tree): no
#          branch is checked out and no hook runs. Each branch is updated locally (when it is not
#          checked out in a work tree) and pushed with a plain fast-forward push; a refused push is
#          reported, never forced.
#       3. Prints a report per branch (ok / conflict / skipped) and the 'git subir' that each final
#          branch still needs so that the pre-push check "behind its parent" passes.
#       -n shows the plan and changes nothing. Only after this, make the fix commits; the fix
#       updates or removes the row.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/git-flow-lib.sh
. "$DIR/git-flow-lib.sh"
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

KB_FILE=KNOWN_BUGS.md

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
kb_die() {
	echo "[bug-conocido] $*" >&2
	exit 1
}

# Print a report line.
# Arguments: $@ message. Returns: 0.
kb_say() { echo "[bug-conocido] $*"; }

# Tell whether a branch name is in the scope of the command.
# Arguments: $1 branch name. Returns: 0 when develop, an ORIGINAL or a final branch of a version
# tree; 1 for main, RELEASE, archived, TESTING and special (SPIKE, CHECKPOINT...) branches.
kb_in_scope() {
	local b="$1"
	[ "$b" = "$QS_BR_MAINLINE" ] && return 0
	is_mainline "$b" && return 1
	is_release_branch "$b" && return 1
	is_ot_release_branch "$b" && return 1
	is_archived_branch "$b" && return 1
	is_testing_branch "$b" && return 1
	[ -z "$(special_kind "$b")" ] || return 1
	valid_branch_name "$b" >/dev/null 2>&1
}

# List the branches in scope, develop first and shallower branches before deeper ones.
# Arguments: none. Returns: 0; prints one branch name per line.
kb_branches() {
	local b
	{
		git for-each-ref --format='%(refname:short)' refs/heads
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin
	} | sort -u | while IFS= read -r b; do
		[ -n "$b" ] && [ "$b" != HEAD ] && kb_in_scope "$b" && echo "$b"
	done | awk -v m="$QS_BR_MAINLINE" '{ d = ($0 == m) ? 0 : gsub("/", "/") + 1; print d, $0 }' |
		sort -n -k1,1 -k2,2 | cut -d' ' -f2-
}

# Tell whether a branch is checked out in another work tree than this one.
# Arguments: $1 branch name. Returns: 0 when it is; 1 otherwise.
kb_checked_out_elsewhere() {
	local here
	here="$(git rev-parse --show-toplevel)"
	git worktree list --porcelain | awk -v b="refs/heads/$1" -v here="$here" '
		$1 == "worktree" { wt = substr($0, 10) }
		$1 == "branch" && $2 == b && wt != here { found = 1 }
		END { exit !found }'
}

# Cherry-pick a commit onto a base with plumbing, keeping author and adding the -x line.
# Arguments: $1 commit, $2 base commit. Returns: 0 and prints the new commit; 1 on a conflict.
kb_pick() {
	local c="$1" base="$2" tree msg
	tree="$(git merge-tree --write-tree --merge-base="$c^" "$base" "$c" 2>/dev/null | head -n1)" || return 1
	msg="$(git log -n1 --format=%B "$c")
(cherry picked from commit $c)"
	GIT_AUTHOR_NAME="$(git log -n1 --format=%an "$c")" GIT_AUTHOR_EMAIL="$(git log -n1 --format=%ae "$c")" \
	GIT_AUTHOR_DATE="$(git log -n1 --format=%aI "$c")" git commit-tree "$tree" -p "$base" -m "$msg"
}

# Add the row to the work tree file, creating the file when it is missing.
# Arguments: $1 date, $2 where, $3 symptom. Returns: 0; exits 1 when the file cannot be created.
kb_add_row() {
	local row
	if [ ! -f "$KB_FILE" ]; then
		git repo-files "$KB_FILE" >/dev/null 2>&1 || true
		[ -f "$KB_FILE" ] || kb_die "$KB_FILE is missing and 'git repo-files $KB_FILE' could not create it"
	fi
	row="| $1 | $2 | $3 | open |"
	# why: keep the file ending with one newline and the row right after the last table line
	[ -z "$(tail -c1 "$KB_FILE")" ] || echo >>"$KB_FILE"
	printf '%s\n' "$row" >>"$KB_FILE"
}

# Copy the commit onto one branch, update it and push it.
# Arguments: $1 commit, $2 branch, $3 "plan" to only describe. Returns: 0; prints the report line.
kb_one() {
	local c="$1" b="$2" plan="$3" base new loc="" rem="" why
	loc="$(git rev-parse -q --verify "refs/heads/$b" || true)"
	rem="$(git rev-parse -q --verify "refs/remotes/origin/$b" || true)"
	base="$(best_ref "$b" || true)"
	if [ -z "$base" ]; then
		kb_say "$b: skipped (no such branch)"
		return 0
	fi
	base="$(git rev-parse "$base^{commit}")"
	if [ -n "$loc" ] && [ -n "$rem" ] && [ "$loc" != "$rem" ] && ! git merge-base --is-ancestor "$loc" "$rem" &&
		! git merge-base --is-ancestor "$rem" "$loc"; then
		kb_say "$b: skipped (local and origin diverged; reconcile with git subir)"
		return 0
	fi
	if [ -n "$loc" ] && [ -n "$rem" ] && [ "$loc" != "$rem" ] && git merge-base --is-ancestor "$rem" "$loc"; then
		kb_say "$b: skipped (unpushed local commits would be published; run git subir first)"
		return 0
	fi
	if git merge-base --is-ancestor "$c" "$base"; then
		kb_say "$b: ok (already has the row)"
		return 0
	fi
	if [ -n "$loc" ] && kb_checked_out_elsewhere "$b"; then
		kb_say "$b: skipped (checked out in another work tree)"
		return 0
	fi
	if ! new="$(kb_pick "$c" "$base")"; then
		kb_say "$b: conflict (cherry-pick by hand: git cherry-pick -x $c)"
		return 0
	fi
	if [ "$plan" = plan ]; then
		kb_say "$b: would add the row$(kb_subir_hint "$b")"
		return 0
	fi
	if [ -n "$loc" ]; then git update-ref -m "bug-conocido: $c" "refs/heads/$b" "$new" "$loc"; fi
	if [ -n "$rem" ] || git remote get-url origin >/dev/null 2>&1; then
		if ! why="$(git push -q origin "$new:refs/heads/$b" 2>&1)"; then
			kb_say "$b: push refused (not forced): $(printf '%s' "$why" | tail -n1)"
			return 0
		fi
	fi
	kb_say "$b: ok$(kb_subir_hint "$b")"
}

# The hint that a final branch needs 'git subir' after its parent received the row.
# Arguments: $1 branch name. Returns: 0; prints the hint (empty for develop and ORIGINALs).
kb_subir_hint() {
	if [ "$1" = "$QS_BR_MAINLINE" ] || is_parent_branch "$1"; then return 0; fi
	printf ' - on it run: git subir'
}

# Entry point.
# Arguments: [-n] "<where>" "<symptom>". Returns: 0; exits 1 on a usage error, a dirty tree, a
# detached HEAD, non-ASCII text or a commit refused by the hooks.
main() {
	local plan=run where raw symptom today cur subject c
	qs_policy_load
	case "${1:-}" in
	-h | --help)
		sed -n '3,15p' "${BASH_SOURCE[0]}"
		return 0
		;;
	-n)
		plan=plan
		shift
		;;
	esac
	[ "$#" -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] || kb_die 'usage: git bug-conocido [-n] "<where>" "<symptom>"'
	where="$1" symptom="$2"
	if LC_ALL=C grep -q '[^ -~]' <<<"$where$symptom"; then kb_die "use ASCII only (no accents)"; fi
	raw="$where"
	where="${where//|/\\|}" symptom="${symptom//|/\\|}"
	cur="$(current_branch)" || kb_die "detached HEAD: check out the fixing branch first"
	today="$(date +%Y-%m-%d)"
	if [ "$plan" = plan ]; then
		kb_say "plan: commit 'docs(bugs): ...' with the row on '$cur', then copy it to:"
		while IFS= read -r b; do
			[ "$b" = "$cur" ] || kb_say "  $b"
		done < <(kb_branches)
		return 0
	fi
	[ -z "$(git status --porcelain --untracked-files=no)" ] || kb_die "the work tree has changes: commit or stash them first"
	if git remote get-url origin >/dev/null 2>&1; then git fetch -q --prune origin 2>/dev/null || true; fi
	subject="docs(bugs): ${raw}"
	subject="${subject:0:50}"
	kb_add_row "$today" "$where" "$symptom"
	git add -- "$KB_FILE"
	git commit -q -m "$subject" -m "Known-bug: $today $raw" || kb_die "the commit was refused; see the message above ($KB_FILE is staged)"
	c="$(git rev-parse HEAD)"
	kb_say "$cur: committed $(git log -n1 --format=%h) (the row)"
	while IFS= read -r b; do
		[ "$b" = "$cur" ] || kb_one "$c" "$b" run
	done < <(kb_branches)
	kb_say "now push '$cur' (git subir) and make the fix commits; the fix updates or removes the row"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
