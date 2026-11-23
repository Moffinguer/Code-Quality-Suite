#!/usr/bin/env bash
# qs-alias: formatear
# git-formatear.sh (git alias: git formatear) - the FORMAT branch of a node (6.0.0 special branches).
#   git formatear [paths...]
#       On '<node>/ORIGINAL' (or on '<node>/FORMAT' itself) creates '<node>/FORMAT' at the ORIGINAL tip
#       with ONE commit 'style: format <scope>' (scope: 'all' or the paths) that holds the output of
#       the suite formatters (engine, Docker) over every file, or over the given files and folders.
#       The commit is made with plumbing in a copy of the tree: no hook runs and the work tree is
#       not touched until the final checkout. When FORMAT exists and holds only such a commit it is
#       reset to the ORIGINAL and regenerated (one commit again); with other commits it is refused.
#       FORMAT is never rebased: after the ORIGINAL moves, run this command again.
#   formatear_ignore_rev <sha> [<scope>]   (function, used by git integra after the squash)
#       appends the squash sha to .git-blame-ignore-revs and sets blame.ignoreRevsFile.
# Test-only: QS_FORMAT_CMD replaces the formatters with a command that takes a file path as its last
# argument (read by engine/qs.py format-check). QS_PUBLISH=0 keeps the branch local.
# Needs branches.flow = squash and the FORMAT type enabled in branches.special.

FMT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# why: the hooks' settings give the image and the suite folder, as for git-rama.sh
FMT_ENV="$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null)/quality-suite.env"
# shellcheck disable=SC1090
[ -f "$FMT_ENV" ] && {
	set -a
	. "$FMT_ENV"
	set +a
}
: "${QUALITY_SUITE_DIR:=$(cd "$FMT_DIR/.." && pwd)}"
# shellcheck disable=SC1091
declare -F qs_policy_load >/dev/null 2>&1 || . "$FMT_DIR/git-flow-lib.sh"
# shellcheck disable=SC1091
. "$FMT_DIR/commit-files-lib.sh"
# shellcheck disable=SC1091
. "$FMT_DIR/qs-docker-lib.sh"
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

FMT_IGNORE_FILE=.git-blame-ignore-revs

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
fmt_die() {
	echo "[formatear] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
fmt_say() { echo "[formatear] $*"; }

# Append a commit to .git-blame-ignore-revs (created when missing, once per sha) and set
# blame.ignoreRevsFile, so 'git blame' skips the formatting commit.
# Arguments: $1 full sha of the squash commit, $2 optional comment (the scope). Returns: 0; 1 when
# the sha is not a commit. Errors: a file that cannot be written stops with the shell's error.
formatear_ignore_rev() {
	local sha root file
	sha="$(git rev-parse -q --verify "$1^{commit}")" || return 1
	root="$(git rev-parse --show-toplevel)"
	file="$root/$FMT_IGNORE_FILE"
	touch "$file"
	if ! grep -qxF "$sha" "$file"; then
		[ -z "${2:-}" ] || printf '# style: format %s\n' "$2" >>"$file"
		printf '%s\n' "$sha" >>"$file"
	fi
	git config blame.ignoreRevsFile "$FMT_IGNORE_FILE"
}

# The scope of the commit message: 'all' or the paths, in the subject when it fits in 50 chars.
# Arguments: $1 scope text ('all' or paths separated by spaces). Returns: 0; prints the subject.
fmt_subject() {
	local s="style: format $1"
	if [ "${#s}" -gt 50 ]; then s="style: format $(wc -w <<<"$1" | tr -d ' ') paths"; fi
	printf '%s' "$s"
}

# The node of the current branch: the folder of '<node>/ORIGINAL' or of '<node>/FORMAT'.
# Arguments: none. Returns: 0 and prints the node; exits through fmt_die when the branch is neither
# the ORIGINAL nor the FORMAT of a node below the version.
fmt_node() {
	local cur node
	cur="$(current_branch)" || fmt_die "detached HEAD: switch to an ORIGINAL first"
	case "$cur" in
	*/FORMAT) node="${cur%/FORMAT}" ;;
	*)
		is_parent_branch "$cur" || fmt_die "'$cur' is not an ORIGINAL: run git formatear on '<node>/$QS_BR_LEAF'"
		node="$(branch_node "$cur")"
		;;
	esac
	valid_branch_name "$node/FORMAT" >/dev/null 2>&1 ||
		fmt_die "FORMAT goes under a node: <version>/<ot>/FORMAT ('$node' is not one)"
	printf '%s' "$node"
}

# Whether every commit of a FORMAT branch not in its ORIGINAL is a format commit (own subject and a
# Format-scope trailer), so the branch can be reset and regenerated.
# Arguments: $1 FORMAT ref, $2 ORIGINAL ref. Returns: 0 when only format commits; 1 otherwise.
fmt_only_format_commits() {
	local c
	while IFS= read -r c; do
		[ -n "$c" ] || continue
		git log -n1 --format=%B "$c" | grep -q '^Format-scope: ' || return 1
		git log -n1 --format=%s "$c" | grep -q '^style: format ' || return 1
	done < <(git rev-list "$2..$1")
	return 0
}

# Build the format commit in a copy of the ORIGINAL tree and move refs/heads/<node>/FORMAT to it.
# Arguments: $1 FORMAT branch, $2 base ref (the ORIGINAL), $3 scope text, $4... paths ('' = all).
# Returns: 0 and prints the new commit sha, or nothing when the formatters change nothing; 1 when
# the engine fails.
fmt_build_commit() {
	local format="$1" base="$2" scope="$3" tmp idx gd tree btree commit msg state
	shift 3
	state="$(qs_state_dir)"
	mkdir -p "$state"
	tmp="$(mktemp -d "$state/format-XXXXXX")"
	idx="$tmp.index"
	gd="$(git rev-parse --absolute-git-dir)"
	git archive "$base" | tar -x -C "$tmp"
	# why: the rules file is git-ignored, so it is not in the archive; the formatters read it
	local rules
	rules="$(git rev-parse --show-toplevel)/.quality-rules.json"
	[ ! -f "$rules" ] || cp "$rules" "$tmp/.quality-rules.json"
	qs_engine_tool "$tmp" format-check --fix "$@" >&2 || {
		rm -rf "$tmp"
		return 1
	}
	rm -f "$tmp/.quality-rules.json"
	btree="$(git rev-parse "$base^{tree}")"
	GIT_INDEX_FILE="$idx" git read-tree "$base"
	# why: pathspec '.' is relative to the directory, which must be the copy and not the repository
	(cd "$tmp" && GIT_INDEX_FILE="$idx" GIT_WORK_TREE="$tmp" GIT_DIR="$gd" git add -A -- .)
	tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
	rm -rf "$tmp" "$idx"
	[ "$tree" != "$btree" ] || return 0
	msg="$(fmt_subject "$scope")"$'\n\n'"$(qs_files_block "$btree" "$tree")"$'\n\n'"Format-scope: $scope"
	commit="$(git commit-tree "$tree" -p "$base" -m "$msg")"
	printf '%s' "$commit"
}

# Publish FORMAT: the new branch through qs_publish_new when the suite has it; a regenerated one
# (already on origin) with a lease on the old tip. A failure is a warning: the local branch stays.
# Arguments: $1 FORMAT branch, $2 sha FORMAT had on origin before ('' when it was not there).
# Returns: 0.
fmt_publish() {
	local b="$1" old="$2"
	[ "${QS_PUBLISH:-1}" != 0 ] || return 0
	git remote get-url origin >/dev/null 2>&1 || {
		fmt_say "no remote origin: $b stays local"
		return 0
	}
	if [ -n "$old" ]; then
		GIT_TERMINAL_PROMPT=0 git push -q --force-with-lease="$b:$old" origin "$b" ||
			echo "[formatear] WARN: $b is not updated on origin (the lease or the push failed). Run git subir" >&2
	elif command -v qs_publish_new >/dev/null 2>&1; then
		qs_publish_new "$b"
	fi
	return 0
}

# git formatear [paths...]: create or regenerate '<node>/FORMAT'. See the file header.
# Arguments: $@ optional files and folders (relative to the directory the command was typed in).
# Returns: 0; exits through fmt_die when a rule refuses it.
cmd_formatear() {
	local node original format base cur scope="all" p rel prefix="${GIT_PREFIX:-}" old="" commit why
	local paths=()
	special_enabled FORMAT || fmt_die "the FORMAT type is not enabled (branches.special)"
	qs_special_need_squash || exit 1
	require_clean || exit 1
	git remote get-url origin >/dev/null 2>&1 && git fetch -q --prune origin 2>/dev/null || true
	node="$(fmt_node)"
	original="$node/$QS_BR_LEAF"
	format="$node/FORMAT"
	why="$(special_migration_lock "${node%%/*}" "$format")" && fmt_die "$why"
	base="$(best_ref "$original")" || fmt_die "'$original' does not exist"
	for p in "$@"; do
		rel="${prefix}${p#./}"
		[ "$p" != . ] || rel="${prefix%/}"
		[ -n "$rel" ] || continue
		git ls-tree -r --name-only "$base" -- "$rel" | grep -q . || fmt_die "no tracked file under '$rel' in $original"
		paths+=("${rel%/}")
	done
	[ "${#paths[@]}" -eq 0 ] || scope="${paths[*]}"
	if git show-ref --verify -q "refs/remotes/origin/$format"; then old="$(git rev-parse "refs/remotes/origin/$format")"; fi
	if git show-ref --verify -q "refs/heads/$format"; then
		fmt_only_format_commits "$format" "$base" ||
			fmt_die "$format has commits that are not format commits: FORMAT holds formatter output only (delete it to start again)"
	fi
	commit="$(fmt_build_commit "$format" "$base" "$scope" ${paths[@]+"${paths[@]}"})" || fmt_die "the formatters failed"
	if [ -z "$commit" ]; then
		fmt_say "nothing to format: the formatters change no file of $original"
		return 0
	fi
	cur="$(current_branch)"
	git update-ref "refs/heads/$format" "$commit"
	if [ "$cur" = "$format" ]; then git reset -q --hard "$commit"; else git checkout -q "$format"; fi
	fmt_say "$format: one commit 'style: format $scope' on $original"
	fmt_publish "$format" "$old"
	return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	qs_policy_load
	cmd_formatear "$@"
fi
