#!/usr/bin/env bash
# git-rama.sh - branch model commands, installed as git aliases (see git-flow-lib.sh):
#   git np  <name>        new PARENT branch: '<node>/<name>/ORIGINAL' (from develop: '<version>/ORIGINAL',
#                         a Semantic Versioning version; 'git np patch|minor|major' takes the next one
#                         after the highest tag / version tree / VERSION, and a first commit writes the
#                         version to VERSION, the pom.xml files and package.json)
#   git nr  <name>        new FINAL branch:  '<node>/<name>' (sibling of the current ORIGINAL's children)
#                         --from <ORIGINAL|develop>: use that branch instead of the current one
#                         (agents in their own worktree, where the ORIGINAL is checked out elsewhere)
#   git convertir-padre   turn the current final branch into a parent ('x/y' -> 'x/y/ORIGINAL')
#   git subir             final: rebase onto its ORIGINAL + push --force-with-lease
#                         ORIGINAL: merge its parent in if behind, then push (never rebased: shared)
#   git integra           final -> its ORIGINAL (rebase, then merge or squash); ORIGINAL -> parent
#                         ORIGINAL (merge --no-ff; children must be integrated first); the top
#                         '<version>/ORIGINAL' gets the version tag and is merged into develop
#                         (branches.flow = merge). flow = squash: the branch is rebased onto its
#                         ORIGINAL and lands there as ONE commit (Commits:, Files:, Refs:,
#                         Squashed:), then it is deleted; '<v>/<ot>/ORIGINAL' goes up by git release
#                         -m "<subject>" [-m "<body>"]: message without opening the editor (agents)
#   git arbol [prefix]    the branch tree: parents, siblings, children, merged/behind state
#   git estructura [file] the whole tree read from stdin (or files): creates what is missing from
#   (git es)              its parent, checks what exists (never recreates), adds new siblings; a new
#                         version tree gets its version commit (VERSION, pom.xml) like git np.
#                         -n/--dry-run: only show the plan; --push: push the branches of the
#                         structure that are not on origin yet (new ones and local-only ones);
#                         --convertir: turn final branches that need children into parents
#   git changelog [tag]   preview of a release: changelog per branch (from the commits in the
#                         version ORIGINAL), recursive check of the tree, the CHANGELOG.md entry
#                         (Common Changelog) with semver advice, plan. Changes nothing.
#                         --version <v> (default: the version of the current branch), -o <file>
#   git release [tag]     step 1 of a release: branches not integrated into their ORIGINAL are set
#                         aside as 'unmerged/<name>'; '<version>/ORIGINAL' becomes '<version>/RELEASE'
#                         with the version commit, CHANGELOG.md and the README badge (separate
#                         commits); RELEASE is pushed and the rest of the tree deleted. Review it.
#                         --version <v>, --yes, --no-push, -n (= changelog)
#                         branches.flow = squash, inside '<v>/<ot>/...' or with --ot <v>/<ot>: the OT
#                         release instead: '<v>/<ot>/RELEASE' = the OT ORIGINAL tip + one
#                         docs(changelog) commit with the OT lines, tag branches.ot_tag on the OT
#                         ORIGINAL tip, RELEASE and tag pushed, the OT subtree deleted (resumable);
#                         git changelog there previews it
#   git publicar [tag]    step 2: '<version>/RELEASE' merged into develop, tagged (annotated with its
#                         CHANGELOG.md entry), pushed, and deleted. --version <v>, --yes, --no-push
#   git nueva-version <v> new version tree '<v>/ORIGINAL' next to the others, from any branch
#   (git nv)              (--from <branch>, default the current one), with its version commit; the
#                         branches below that branch are copied under '<v>/' keeping their path below
#                         the version, each with its work and merged with its new parent;
#                         --arbol-completo: every branch of that version tree. -n: only the plan
#   git combinar          several '<v>/RELEASE' into one: asks yes/no for each and the version; on
#                         develop, one squash commit per RELEASE (creation order, oldest first) with
#                         only its own changes (develop merged in first, as a temporary commit, when
#                         a RELEASE lacks it), then the version, CHANGELOG.md and README badge of
#                         '<version>/RELEASE'; the ones combined are kept as 'unmerged/<v>/RELEASE'.
#                         --version <v>, --incluir <v1,v2...>, --yes
#   git repo-files [NAME] the standard repository files that are missing (README, CHANGELOG, VERSION,
#                         CONTRIBUTING, ... DEVELOPMENT), filled from git history and pom.xml; never
#                         overwrites; --force NAME regenerates one; -n shows the plan
# Long names: git nueva-padre / git nueva-final. Options: --yes (no prompts), --force.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$DIR/.." && pwd)"
HOOK_ENV="$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null)/quality-suite.env"
# shellcheck disable=SC1090
[ -f "$HOOK_ENV" ] && {
	set -a
	. "$HOOK_ENV"
	set +a
}
: "${QUALITY_SUITE_DIR:=$SUITE}"
# shellcheck disable=SC1091
. "$DIR/git-flow-lib.sh"
# why: the Files block of the squash commits is rendered by the commit-message library when it
# is installed (5.0.0-RC1/git/log); squash_files_block falls back to the same format without it
# shellcheck disable=SC1091
[ -f "$DIR/commit-files-lib.sh" ] && . "$DIR/commit-files-lib.sh"
qs_policy_load

die() {
	echo "[rama] $*" >&2
	exit 1
}
say() { echo "[rama] $*"; }
YES=0 FORCE=0 FROM="" MSG=() ARGS=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--yes | -y) YES=1 ;;
	--force) FORCE=1 ;;
	--from)
		[ "$#" -ge 2 ] || die "--from needs a branch"
		FROM="$2"
		shift
		;;
	--from=*) FROM="${1#--from=}" ;;
	-m)
		[ "$#" -ge 2 ] || die "-m needs a message"
		MSG+=("$2")
		shift
		;;
	*) ARGS+=("$1") ;;
	esac
	shift
done
set -- ${ARGS[@]+"${ARGS[@]}"}
CMD="${1:-}"
shift || true
has_origin() { git remote get-url origin >/dev/null 2>&1; }
fetch_origin() { has_origin && git fetch -q --prune origin 2>/dev/null || true; }
confirm() {
	[ "$YES" = 1 ] && return 0
	local r
	printf '%s [y/N] ' "$1" >/dev/tty
	read -r r </dev/tty || r=""
	case "$r" in y | Y | s | S | yes | si) return 0 ;; esac
	return 1
}
exists_ref() { git rev-parse -q --verify "$1" >/dev/null 2>&1; }
# git_idx <index file> <git arguments>...: run git on a temporary index instead of the real one.
# Arguments: $1 the index file; $2... the git command. Exit status: the one of git.
git_idx() {
	local idx="$1"
	shift
	GIT_INDEX_FILE="$idx" git "$@"
}
# any local or remote branch named exactly <b>, or under the folder <b>/
taken() {
	exists_ref "refs/heads/$1" || exists_ref "refs/remotes/origin/$1" ||
		[ -n "$(git for-each-ref --count=1 "refs/heads/$1/" "refs/remotes/origin/$1/")" ]
}

# --- versions: Semantic Versioning (https://semver.org) ----------------------------------------
SEMVER_RELEASE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
# released or planned versions, lowest first: tags (a 'v' prefix is fine), version trees (also the
# ones set aside), the VERSION file of the mainline
known_versions() {
	local m
	m="$(best_ref "$QS_BR_MAINLINE" || true)"
	{
		git tag -l | sed 's/^[vV]//'
		all_branches | awk -F/ -v a="$QS_BR_ARCHIVE" 'NF > 1 { print ($1 == a ? $2 : $1) }'
		if [ -n "$m" ] && [ -n "$QS_BR_VERSION_FILE" ]; then git show "$m:$QS_BR_VERSION_FILE" 2>/dev/null || true; fi
	} | tr -d '\r ' | { grep -E "$SEMVER_RELEASE" || true; } | sort -t. -k1,1n -k2,2n -k3,3n -u
}
next_version() { # major|minor|patch -> the version after the highest known one
	local last ma mi pa
	last="$(known_versions | tail -n1)"
	last="${last:-0.0.0}"
	IFS=. read -r ma mi pa <<<"$last"
	case "$1" in
	major) echo "$((ma + 1)).0.0" ;; minor) echo "$ma.$((mi + 1)).0" ;; patch) echo "$ma.$mi.$((pa + 1))" ;;
	esac
}
version_subject() {
	local s="chore(version): $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: $1"
	printf '%s' "$s"
}

# The engine of the suite image, for edits that need a parser (pom.xml, CHANGELOG.md).
engine() { # engine <folder> <qs.py command> [args...]
	# shellcheck disable=SC1091
	[ -n "${QS_DOCKER_LIB:-}" ] || {
		. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"
		QS_DOCKER_LIB=1
	}
	command -v docker >/dev/null 2>&1 || return 1
	qs_engine_tool "$@"
}

# version_commit <branch> <version>: one commit on <branch> (without checking it out) that writes
# the version to VERSION, the pom.xml files that share the root version and package.json
# (branches.pom_version decides: update, snapshot, check, off). Nothing when they already hold it.
version_commit() {
	local b="$1" v="$2" parent gd tmp changed f blob mode tree commit
	[ -n "$QS_BR_VERSION_FILE" ] || [ "$QS_BR_POM" != off ] || return 0
	parent="$(git rev-parse "refs/heads/$b")"
	gd="$(git rev-parse --absolute-git-dir)/quality-suite"
	tmp="$gd/version-tmp"
	rm -rf "$tmp" "$tmp.index"
	mkdir -p "$tmp"
	# why: only the files that hold the version, as committed on the branch (the work tree is untouched)
	git ls-tree -r -z --name-only "$parent" | { grep -zE '(^|/)(pom\.xml|package\.json)$' || true; } >"$gd/version.list"
	if [ -n "$QS_BR_VERSION_FILE" ] && git cat-file -e "$parent:$QS_BR_VERSION_FILE" 2>/dev/null; then
		printf '%s\0' "$QS_BR_VERSION_FILE" >>"$gd/version.list"
	fi
	if [ -s "$gd/version.list" ]; then xargs -0 git archive --format=tar "$parent" <"$gd/version.list" | tar -xi -C "$tmp"; fi
	if changed="$(engine "$tmp" version-set "$v" --pom "$QS_BR_POM" --version-file "$QS_BR_VERSION_FILE" 2>"$gd/version.err")"; then
		sed 's/^\[quality-suite\] /[rama] /' "$gd/version.err" >&2
	else
		echo "[rama] WARN: the suite image could not run (Docker): only $QS_BR_VERSION_FILE is written." >&2
		[ "$QS_BR_POM" = off ] || echo "       pom.xml: mvn versions:set -DnewVersion=$v -DgenerateBackupPoms=false" >&2
		changed=""
		if [ -n "$QS_BR_VERSION_FILE" ] && [ "$(cat "$tmp/$QS_BR_VERSION_FILE" 2>/dev/null)" != "$v" ]; then
			mkdir -p "$(dirname "$tmp/$QS_BR_VERSION_FILE")"
			printf '%s\n' "$v" >"$tmp/$QS_BR_VERSION_FILE"
			changed="$QS_BR_VERSION_FILE"
		fi
	fi
	changed="$(printf '%s\n' "$changed" | tr -d '\r' | grep -v '^$' || true)"
	if [ -n "$changed" ]; then
		git_idx "$tmp.index" read-tree "$parent"
		while IFS= read -r f; do
			blob="$(git hash-object -w --path="$f" "$tmp/$f")"
			mode="$(git ls-tree --full-tree "$parent" -- "$f" | awk '{print $1}')"
			git_idx "$tmp.index" update-index --add --cacheinfo "${mode:-100644},$blob,$f"
		done <<<"$changed"
		tree="$(git_idx "$tmp.index" write-tree)"
		commit="$(git commit-tree "$tree" -p "$parent" -m "$(version_subject "$v")")"
		git update-ref "refs/heads/$b" "$commit" "$parent"
		say "$b: version $v in $(printf '%s' "$changed" | tr '\n' ' ')"
	fi
	rm -rf "$tmp" "$tmp.index" "$gd/version.list" "$gd/version.err"
}

# Create a new branch under the current node (git np / git nr).
#
# Args:
#   $1  kind: padre (parent, ends in the ORIGINAL leaf) or final
#   $2  name: one segment; the version from develop, the OT or a detail below it
# Returns: 0 on success; exits through die when the name is empty, has a '/', is reserved
#   (the ORIGINAL or RELEASE leaf) or the resulting branch name breaks the policy.
cmd_nueva() {
	local kind="$1" seg="${2:-}" cur node new base
	[ -n "$seg" ] || die "usage: git $([ "$kind" = padre ] && echo np || echo nr) <name>"
	case "$seg" in */*) die "the name is one segment (no '/'): $seg" ;; "$QS_BR_LEAF" | "$QS_BR_RELEASE_LEAF") die "'$seg' is reserved" ;; esac
	if [ -n "$FROM" ]; then
		fetch_origin
		cur="$FROM"
		exists_ref "refs/heads/$cur" || exists_ref "refs/remotes/origin/$cur" || die "--from: branch '$cur' not found"
	else
		cur="$(current_branch)" || die "detached HEAD"
	fi
	if [ "$cur" = "$QS_BR_MAINLINE" ]; then
		[ "$kind" = padre ] || die "a version branch is always a parent: git np $seg  (creates $seg/$QS_BR_LEAF)"
		case "$seg" in
		major | minor | patch)
			fetch_origin
			local last
			last="$(known_versions | tail -n1)"
			seg="$(next_version "$seg")"
			say "next ${2} version after ${last:-none}: $seg"
			;;
		esac
		new="$seg/$QS_BR_LEAF"
	elif is_parent_branch "$cur"; then
		node="$(branch_node "$cur")"
		new="$node/$seg"
		[ "$kind" = padre ] && new="$new/$QS_BR_LEAF"
	else
		die "'$cur' is a final branch and cannot have children. Make it a parent first: git convertir-padre"
	fi
	local why
	why="$(valid_branch_name "$new")" || die "invalid name '$new': $why"
	fetch_origin
	taken "${new%/"$QS_BR_LEAF"}" && die "'${new%/"$QS_BR_LEAF"}' already exists (as a branch or a folder of branches)"
	base="$(best_ref "$cur")"
	base="${base:-$cur}"
	git branch -q --no-track "$new" "$base"
	# why: the version tree starts with its version written down, so every branch below inherits it
	[ "$cur" = "$QS_BR_MAINLINE" ] && version_commit "$new" "$seg"
	git checkout -q "$new"
	say "created '$new' from '$base' (parent: $(parent_branch "$new"))"
	[ "$kind" = padre ] && say "children: git np <name> (parent) / git nr <name> (final)"
	return 0
}

convert_branch() { # final branch '<F>/<x>' -> '<F>/<x>/ORIGINAL', local and on origin
	local cur="$1" new remote=0
	is_mainline "$cur" && die "'$cur' is a mainline branch"
	is_parent_branch "$cur" && die "'$cur' is already a parent branch"
	valid_branch_name "$cur" >/dev/null || die "'$cur' does not follow the branch model"
	new="$cur/$QS_BR_LEAF"
	if has_origin && git ls-remote --exit-code --heads origin "refs/heads/$cur" >/dev/null 2>&1; then remote=1; fi
	if [ "$remote" = 1 ]; then
		echo "[rama] '$cur' exists on origin. Converting it deletes origin/$cur and pushes '$new'." >&2
		echo "       Anyone else with '$cur' must run: git fetch --prune && git checkout $new" >&2
		confirm "Continue?" || die "cancelled"
	fi
	# why: a branch that only exists on origin gets its local copy first, then the same rename
	exists_ref "refs/heads/$cur" || git branch -q --no-track "$cur" "origin/$cur"
	git branch -m "$cur" "$new"
	if [ "$remote" = 1 ]; then
		git push -q origin --delete "$cur"
		git push -q -u origin "$new"
	fi
}

cmd_convertir() {
	local cur
	cur="$(current_branch)" || die "detached HEAD"
	fetch_origin
	convert_branch "$cur"
	say "'$cur' is now '$cur/$QS_BR_LEAF'. Create children with: git np <name> / git nr <name>"
}

cmd_subir() {
	local cur parent base
	cur="$(current_branch)" || die "detached HEAD"
	require_clean
	parent="$(parent_branch "$cur")"
	fetch_origin
	if is_parent_branch "$cur" || is_mainline "$cur"; then
		# why: an ORIGINAL is shared (children are based on it): bring changes in with merges, never rebase
		if exists_ref "refs/remotes/origin/$cur" && ! git merge-base --is-ancestor "origin/$cur" "$cur"; then
			say "merging origin/$cur (others pushed to it)..."
			git merge -q --no-edit "origin/$cur" || die "conflicts: resolve, 'git commit', then re-run git subir"
		fi
		if is_parent_branch "$cur" && [ -n "$parent" ]; then
			base="$(best_ref "$parent" || true)"
			if [ -n "$base" ] && ! git merge-base --is-ancestor "$base" "$cur"; then
				say "merging the parent '$base' into '$cur'..."
				git merge -q --no-edit "$base" || die "conflicts: resolve, 'git commit', then re-run git subir"
			fi
		fi
		has_origin && {
			say "pushing $cur..."
			git push -q origin "$cur"
		}
	else
		base="$(best_ref "$parent")"
		[ -n "$base" ] || die "parent '$parent' not found locally or on origin"
		if ! git merge-base --is-ancestor "$base" "$cur"; then
			say "rebasing $cur onto $base..."
			git rebase -q "$base" || die "conflicts: resolve, 'git rebase --continue', then re-run git subir (rerere remembers)"
		fi
		has_origin && {
			say "pushing $cur (--force-with-lease)..."
			git push -q --force-with-lease origin "$cur"
		}
	fi
	say "done."
}

# git with its chatter ("Automatic merge went well; stopped before committing...") shown only on failure
quiet_merge() {
	local out
	out="$(git "$@" 2>&1)" && return 0
	printf '%s\n' "$out" >&2
	return 1
}

compose_message() { # $1 = source branch, $2 = target, $3 = file
	local src="$1" dst="$2" out="$3" scope commits manifest
	scope="$(branch_node "$src")"
	scope="${scope##*/}"
	commits="$(git log --reverse --no-merges --format='- %h %s' "$dst..$src" || true)"
	manifest="$(git -c core.quotePath=true diff --name-status "$dst...$src" || true)"
	{
		echo "feat($scope): DESCRIPCION_BREVE"
		echo ""
		echo "DESCRIPCION_DETALLADA"
		echo ""
		echo "Refs: $src -> $dst"
		echo ""
		echo "Commits:"
		printf '%s\n' "$commits"
		echo ""
		echo "Files:"
		printf '%s\n' "$manifest"
		echo ""
		echo "# Fill the subject and DESCRIPCION_DETALLADA (ASCII only). '#' lines are removed."
	} >"$out"
}

# --- git integra with branches.flow = squash ---------------------------------------------------

# squash_files_block <base> <rev>: print the "Files:" block of base..rev: one "<status> <path>"
# line per file (renames "R <old> -> <new>", non-ASCII paths escaped by core.quotePath, a path
# with a space quoted: 'A "sp ace.txt"', 'R "a b" -> "c d"'), or "(none)" when nothing changed.
# Uses qs_files_block of commit-files-lib.sh when it is loaded, otherwise renders the same
# format. Returns 0.
squash_files_block() {
	local base="$1" rev="$2" out
	if declare -F qs_files_block >/dev/null; then
		qs_files_block "$base" "$rev"
		return 0
	fi
	out="$(git -c core.quotePath=true diff --name-status -M "$base" "$rev" 2>/dev/null || true)"
	echo "Files:"
	if [ -z "$out" ]; then
		echo "(none)"
		return 0
	fi
	printf '%s\n' "$out" | awk -F '\t' '{
		s = substr($1, 1, 1)
		# why: a path with a space is quoted the way git quotes (renames are ambiguous otherwise)
		for (i = 2; i <= NF; i++) if (index($i, " ") > 0 && substr($i, 1, 1) != "\"") $i = "\"" $i "\""
		if ((s == "R" || s == "C") && NF >= 3) print s " " $2 " -> " $3
		else print s " " $2
	}'
}

# squash_commits_block <base> <rev>: print the "Commits:" block of base..rev, oldest first,
# merges left out: "- <short hash> <subject>", followed by the Commits: lines of a squashed
# squash indented by two spaces, so the nesting is kept at every level. Returns 0.
squash_commits_block() {
	local base="$1" rev="$2" h
	echo "Commits:"
	while IFS= read -r h; do
		[ -n "$h" ] || continue
		git log -1 --format='- %h %s' "$h"
		git log -1 --format=%B "$h" | awk '
			/^Commits:$/ { on = 1; next }
			on && /^ *- / { print "  " $0; next }
			on { exit }'
	done < <(git rev-list --reverse --no-merges "$base..$rev")
}

# squash_norms <base> <rev> [text]: print the union of the norm ids named by the 'Norms:' lines
# of the commits base..rev and of text (ids split on commas and blanks, first seen first, comma
# separated). Prints 'none' when the lines only say none, nothing when there is no such line.
# Returns 0.
squash_norms() {
	local base="$1" rev="$2" text="${3:-}"
	{
		git log --no-merges --format=%B "$base..$rev"
		printf '%s\n' "$text"
	} | sed -n 's/^Norms:[[:space:]]*//p' | tr -s ', \t' '\n' | awk '
		$0 == "" { next }
		tolower($0) == "none" { none = 1; next }
		!seen[$0]++ { out = out (out == "" ? "" : ", ") $0 }
		END { if (out != "") print out; else if (none) print "none" }'
}

# compose_squash_message <source> <target> <file> [text]: write the squash commit message
# template of <source> (already rebased onto <target>) into <file>: placeholder subject and
# body, Commits: and Files: of target..source, then the trailers Norms: (union, also of the
# 'Norms:' lines of text; 'Norms: none' when no commit names any), 'Refs: <source> -> <target>' (read by the changelog engine) and
# 'Squashed: <source> <full sha>' (read by the integrated checks). Returns 0.
compose_squash_message() {
	local src="$1" dst="$2" out="$3" text="${4:-}" scope norms
	scope="$(branch_node "$src")"
	scope="${scope##*/}"
	norms="$(squash_norms "$dst" "$src" "$text")"
	norms="${norms:-none}"
	{
		echo "feat($scope): DESCRIPCION_BREVE"
		echo ""
		echo "DESCRIPCION_DETALLADA"
		echo ""
		squash_commits_block "$dst" "$src"
		squash_files_block "$dst" "$src"
		echo ""
		echo "Norms: $norms"
		echo "Refs: $src -> $dst"
		echo "Squashed: $src $(git rev-parse "$src^{commit}")"
		echo ""
		echo "# Fill the subject and DESCRIPCION_DETALLADA (ASCII only). '#' lines are removed."
	} >"$out"
}

# checked_out_elsewhere <branch>: succeed when <branch> is checked out in a worktree other than
# the current one. Returns: 0 checked out elsewhere, 1 otherwise.
checked_out_elsewhere() {
	local me
	me="$(git rev-parse --show-toplevel)"
	git worktree list --porcelain | awk -v b="branch refs/heads/$1" -v me="$me" '
		/^worktree / { w = substr($0, 10) }
		$0 == b && w != me { f = 1 }
		END { exit !f }'
}

# rebase_in_progress: succeed while a rebase of the current worktree is stopped.
rebase_in_progress() {
	local gd
	gd="$(git rev-parse --absolute-git-dir)"
	[ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]
}

# integra_rebase <branch> <onto> <bypass>: rebase the current branch <branch> onto <onto> (nothing
# to do when it already contains it). Steps whose conflicts rerere resolved are continued; any
# other conflict aborts the rebase, so the branch, its parent and the work tree stay as they
# were. <bypass> 1 lets pre-rebase accept an ORIGINAL with pending children (--force).
# Returns 0 when rebased; exits through die on a conflict or a refused rebase.
integra_rebase() {
	local b="$1" onto="$2" bypass="$3" before how
	git merge-base --is-ancestor "$onto" "$b" && return 0
	say "rebasing $b onto $onto..."
	QUALITY_ALLOW_REBASE="$bypass" git rebase -q "$onto" && return 0
	if is_parent_branch "$b"; then
		how="git subir merges '$onto' into '$b': resolve there (rerere remembers)"
	else
		how="git subir rebases '$b': resolve, 'git rebase --continue'"
	fi
	while rebase_in_progress; do
		before="$(git rev-parse HEAD)"
		if [ -z "$(git ls-files -u)" ] && GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then continue; fi
		if [ -n "$(git ls-files -u)" ] || [ "$(git rev-parse HEAD)" = "$before" ]; then
			git rebase --abort 2>/dev/null || true
			die "conflicts rebasing '$b' onto '$onto'; nothing was changed. Solve them first ($how), then re-run git integra"
		fi
	done
	git merge-base --is-ancestor "$onto" "$b" ||
		die "'$b' was not rebased onto '$onto' (see the messages above); nothing was changed"
}

# squash_drop_child <branch>: delete the integrated <branch> locally and on origin (-D: a squashed
# branch is not an ancestor of its parent). Asks first unless --yes; when the answer is no (or
# there is no terminal) it keeps the branch and prints the commands. A kept branch that was
# rebased no longer descends from its origin copy: it warns, prints the safe update command
# (git push --force-with-lease origin <branch>) and offers to run it after a confirmation (never
# silently, never with --yes, which deletes instead). Returns 0.
squash_drop_child() {
	local b="$1" where="locally"
	exists_ref "refs/remotes/origin/$b" && where="locally and on origin"
	if ! confirm "delete the integrated '$b' $where?" 2>/dev/null; then
		say "kept '$b'. Delete it: git branch -D $b$(exists_ref "refs/remotes/origin/$b" && echo " && git push origin --delete $b")"
		if exists_ref "refs/remotes/origin/$b" && ! git merge-base --is-ancestor "refs/remotes/origin/$b" "$b"; then
			say "WARNING: '$b' was rebased and now diverges from origin/$b: a plain push is rejected."
			say "Update origin safely (pre-push needs the bypass: the branch is behind its parent now): QUALITY_SKIP_PARENT_CHECK=1 git push --force-with-lease origin $b"
			if confirm "run it now (force-with-lease)?" 2>/dev/null; then
				QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$b" || say "could not update '$b' on origin"
			fi
		fi
		return 0
	fi
	git branch -q -D "$b" || say "could not delete '$b' locally (checked out in another worktree?)"
	if exists_ref "refs/remotes/origin/$b"; then
		git push -q origin --delete "$b" || say "could not delete '$b' on origin"
	fi
	say "deleted '$b' $where"
}

# integra_squash <branch> <parent>: git integra with branches.flow = squash. A final branch, or a
# '<F>/ORIGINAL' below the OT whose children are all integrated (--force: even when not), is
# rebased onto <parent> and lands there as ONE single-parent commit (message: subject and body
# from -m or the editor, Commits:, Files:, Norms:, Refs:, Squashed:); then it is deleted
# (confirmation unless --yes). Refused: '<v>/<ot>/ORIGINAL' and '<v>/ORIGINAL' (git release),
# <branch> or <parent> checked out in another worktree, nothing to integrate.
# Returns 0; exits through die when refused or on a conflict (nothing changed).
integra_squash() {
	local cur="$1" parent="$2" pending bypass=0 tpl editor subject text="" m
	if is_parent_branch "$cur"; then
		[ "$(branch_depth "$cur")" -ge 3 ] ||
			die "'$cur' goes up through a release, not git integra (branches.flow = squash): git release"
		pending="$(children_pending "$cur")"
		if [ -n "$pending" ]; then
			[ "$FORCE" = 1 ] || [ "$QS_BR_REQUIRE_CHILDREN" != 1 ] ||
				die "children not integrated yet: $pending  (integrate them first, or --force)"
			bypass=1
			if ! git merge-base --is-ancestor "$parent" "$cur"; then
				say "WARNING: rebasing '$cur' onto '$parent' leaves these children orphaned (each must run git subir afterwards): $pending"
				confirm "rebase '$cur' under them anyway?" 2>/dev/null || die "cancelled; nothing was changed"
			fi
		fi
	fi
	for m in "$cur" "$parent"; do
		! checked_out_elsewhere "$m" || die "'$m' is checked out in another worktree: free it there first (git switch -)"
	done
	[ -n "$(git rev-list -n1 "$parent..$cur")" ] || die "'$cur' has nothing that '$parent' lacks; nothing to integrate"
	integra_rebase "$cur" "$parent" "$bypass"
	tpl="$(git rev-parse --absolute-git-dir)/quality-suite/INTEGRA_MSG"
	mkdir -p "$(dirname "$tpl")"
	[ "${#MSG[@]}" -gt 1 ] && text="$(printf '%s\n' "${MSG[@]:1}")"
	compose_squash_message "$cur" "$parent" "$tpl" "$text"
	if [ "${#MSG[@]}" -gt 0 ]; then
		# why: agents cannot drive an editor; their Norms: lines go into the Norms: trailer
		{
			printf '%s\n\n' "${MSG[0]}"
			for m in "${MSG[@]:1}"; do
				m="$(printf '%s\n' "$m" | grep -v '^Norms:' || true)"
				[ -z "$m" ] || printf '%s\n\n' "$m"
			done
			awk 'f || /^Commits:$/{f=1} f' "$tpl"
		} >"$tpl.new" && mv "$tpl.new" "$tpl"
	else
		editor="${GIT_EDITOR:-$(git config core.editor 2>/dev/null || echo "${EDITOR:-vi}")}"
		eval "$editor \"\$tpl\""
	fi
	subject="$(grep -vE '^[[:space:]]*#' "$tpl" | grep -vE '^[[:space:]]*$' | head -n1 || true)"
	case "$subject" in *DESCRIPCION_BREVE* | "") die "subject not filled in; nothing was integrated ('$cur' is rebased onto '$parent')" ;; esac
	say "$cur -> $parent (squash)"
	git checkout -q "$parent"
	if ! quiet_merge -c merge.ff=true merge -q --squash "$cur" || ! git commit -q --allow-empty --cleanup=strip -F "$tpl"; then
		git reset -q --hard HEAD
		git checkout -q "$cur"
		die "the squash commit into '$parent' failed (see above); '$parent' is unchanged"
	fi
	say "done: '$cur' integrated into '$parent' as $(git rev-parse --short HEAD). Push: git push origin $parent"
	squash_drop_child "$cur"
}

cmd_integra() {
	local cur parent base mode tpl tag depth unmerged="" c cref editor subject
	cur="$(current_branch)" || die "detached HEAD"
	valid_branch_name "$cur" >/dev/null || die "'$cur' does not follow the branch model"
	is_mainline "$cur" && die "'$cur' is a mainline branch; nothing to integrate"
	parent="$(parent_branch "$cur")"
	[ -n "$parent" ] || die "'$cur' has no parent"
	require_clean
	fetch_origin
	if ! exists_ref "refs/heads/$parent"; then
		exists_ref "refs/remotes/origin/$parent" || die "parent '$parent' does not exist (create it with git np)"
		git branch -q "$parent" "origin/$parent"
	elif exists_ref "refs/remotes/origin/$parent" && git merge-base --is-ancestor "$parent" "origin/$parent"; then
		git branch -q -f "$parent" "origin/$parent" 2>/dev/null || true # fast-forward the local parent
	fi
	if [ "${QS_BR_FLOW:-merge}" = squash ]; then
		integra_squash "$cur" "$parent"
		return 0
	fi
	if is_parent_branch "$cur"; then
		if [ "$QS_BR_REQUIRE_CHILDREN" = 1 ] && [ "$FORCE" != 1 ]; then
			while IFS= read -r c; do
				[ -n "$c" ] || continue
				cref="$(best_ref "$c")"
				[ -n "$cref" ] || continue
				git merge-base --is-ancestor "$cref" "$cur" || unmerged="$unmerged $c"
			done < <(branch_children "$cur")
			[ -z "$unmerged" ] || die "children not integrated yet:$unmerged  (integrate them first, or --force)"
		fi
		mode=merge
		depth="$(branch_depth "$cur")"
		if [ "${QS_BR_TAG_LEVEL:-0}" -gt 0 ] && [ "$depth" -eq "$QS_BR_TAG_LEVEL" ]; then
			tag="$(render_tag "$cur")"
			if exists_ref "refs/tags/$tag"; then
				[ "$(git rev-parse "refs/tags/$tag^{commit}")" = "$(git rev-parse "$cur")" ] ||
					die "tag '$tag' already exists on another commit (change branches.tag, e.g. '{version}-{ot}')"
			else
				git tag -a "$tag" -m "Release $tag ($cur)" "$cur"
				say "tag '$tag' created on $cur (push it: git push origin $tag)"
			fi
		fi
	else
		base="$(best_ref "$parent")"
		if ! git merge-base --is-ancestor "$base" "$cur"; then
			say "rebasing $cur onto $base (siblings are rebased onto their ORIGINAL)..."
			git rebase -q "$base" || die "conflicts: resolve, 'git rebase --continue', then re-run git integra"
		fi
		mode="$QS_BR_LEAF_MERGE"
	fi
	tpl="$(git rev-parse --absolute-git-dir)/quality-suite/INTEGRA_MSG"
	mkdir -p "$(dirname "$tpl")"
	compose_message "$cur" "$parent" "$tpl"
	if [ "${#MSG[@]}" -gt 0 ]; then
		# why: agents cannot drive an editor; keep the generated Refs/Commits/Files part
		{
			printf '%s\n\n' "${MSG[0]}"
			[ "${#MSG[@]}" -gt 1 ] && printf '%s\n\n' "${MSG[@]:1}"
			awk 'f || /^Refs: /{f=1} f' "$tpl"
		} >"$tpl.new" && mv "$tpl.new" "$tpl"
	else
		editor="${GIT_EDITOR:-$(git config core.editor 2>/dev/null || echo "${EDITOR:-vi}")}"
		eval "$editor \"\$tpl\""
	fi
	subject="$(grep -vE '^[[:space:]]*#' "$tpl" | grep -vE '^[[:space:]]*$' | head -n1 || true)"
	case "$subject" in *DESCRIPCION_BREVE* | "") die "subject not filled in; nothing was merged" ;; esac
	say "$cur -> $parent ($([ "$mode" = squash ] && echo 'squash' || echo 'merge --no-ff'))"
	git checkout -q "$parent"
	if [ "$mode" = squash ]; then
		quiet_merge -c merge.ff=true merge -q --squash "$cur" || die "conflicts in '$parent': resolve, then: git commit -F '$tpl' --cleanup=strip"
	else
		quiet_merge merge -q --no-ff --no-commit "$cur" || die "conflicts in '$parent': resolve, then: git commit -F '$tpl' --cleanup=strip"
	fi
	git commit -q --cleanup=strip -F "$tpl"
	say "done: '$cur' integrated into '$parent'. Push: git push origin $parent${tag:+ $tag}"
	is_parent_branch "$cur" || say "the final branch can go: git branch -d $cur$(exists_ref "refs/remotes/origin/$cur" && echo " && git push origin --delete $cur")"
}

cmd_arbol() {
	local cur prefix
	cur="$(current_branch || true)"
	prefix="${1:-}"
	if [ -z "$prefix" ] && [ -n "$cur" ] && ! is_mainline "$cur"; then prefix="$(branch_version "$cur")"; fi
	{
		git for-each-ref --format='%(refname:short)' refs/heads/
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | { grep -v '^HEAD$' || true; }
	} | sort -u |
		while IFS= read -r b; do
			[ -z "$prefix" ] || case "$b" in "$prefix"/* | "$prefix") ;; *) continue ;; esac
			is_mainline "$b" && continue
			if is_archived_branch "$b"; then
				printf '~\t%s\n' "$b"
			elif valid_branch_name "$b" >/dev/null 2>&1; then
				printf '%s\t%s\n' "$(branch_node "$b")" "$b"
			else printf '~\t%s\n' "$b"; fi
		done | LC_ALL=C sort -t "$(printf '\t')" -k1,1 |
		while IFS="$(printf '\t')" read -r node b; do
			local ind="" p pref ref st="" i depth ahead behind
			if [ "$node" = "~" ]; then
				if is_archived_branch "$b"; then echo "~  $b   (set aside by git release)"; else echo "!  $b   (off-model)"; fi
				continue
			fi
			depth="$(awk -F/ '{print NF}' <<<"$node")"
			for ((i = 1; i < depth; i++)); do ind="$ind   "; done
			p="$(parent_branch "$b")"
			pref="$(best_ref "$p" || true)"
			ref="$(best_ref "$b" || true)"
			if [ -n "$pref" ] && [ -n "$ref" ]; then
				ahead="$(git rev-list --count "$pref..$ref")"
				behind="$(git rev-list --count "$ref..$pref")"
				if [ "$ahead" = 0 ]; then st=" (nothing pending for $p)"; else
					st=" (+$ahead pending"
					[ "$behind" = 0 ] && st="$st)" || st="$st, $behind behind $p)"
				fi
			fi
			exists_ref "refs/heads/$b" || st="$st (remote only)"
			printf '%s%s %s%s%s\n' "$ind" "$(is_parent_branch "$b" && echo '+' || echo '-')" "$b" \
				"$([ "$b" = "$cur" ] && echo '  <- you are here')" "$st"
		done
	return 0
}

# --- git estructura -------------------------------------------------------------------------
# Input: one branch per line, as a path, as an indented tree, or both ('git arbol' output works
# too: its markers and annotations are ignored; '#' starts a comment):
#   6.22.6/188858/RF001/login             6.22.6
#   6.22.6/188858/RF001/bank/bugfix         188858
#   6.22.6/188858/RF001/bank/payments         RF001
#                                               login
#                                               bank
#                                                 bugfix
#                                                 payments
# A node with children, or written with a trailing '/' or '/ORIGINAL', is a parent; a version is
# always a parent; every other node is a final branch. A root line 'develop' (the mainline) is
# allowed and ignored.
parse_structure() { # stdin -> "P|F<TAB>node" lines, ancestors first, in input order
	tr -d '\r' | awk -v leaf="$QS_BR_LEAF" -v main="$QS_BR_MAINLINE" '
    function add(node, par,   n, k, a, p) {
      n = split(node, a, "/"); p = ""
      for (k = 1; k <= n; k++) {
        p = (k == 1) ? a[1] : p "/" a[k]
        if (!(p in seen)) { seen[p] = 1; order[++cnt] = p }
        if (k < n || k == 1) isp[p] = 1
      }
      if (par) isp[node] = 1
    }
    { sub(/#.*/, "") }
    /^[ \t]*!/ { next }                                  # off-model lines of git arbol
    match($0, /[A-Za-z0-9]/) == 0 { next }
    {
      w = RSTART; t = substr($0, RSTART); sub(/[ \t].*/, "", t); par = 0
      if (t ~ /\/$/) { par = 1; sub(/\/+$/, "", t) }
      if (t == leaf) t = ""
      else if (substr(t, length(t) - length(leaf)) == "/" leaf) { par = 1; t = substr(t, 1, length(t) - length(leaf) - 1) }
      while (sp > 0 && sind[sp] >= w) sp--
      # why: a tree may start at develop; it is the root, not a branch to create
      if (t == main || t == "main" || t == "master") { spath[++sp] = ""; sind[sp] = w; next }
      pp = (sp > 0) ? spath[sp] : ""
      if (t == "") { if (pp != "") isp[pp] = 1; next }
      # why: an indented line may repeat the full path (git arbol) or give only the rest
      if (pp == "" || t == pp || index(t, pp "/") == 1) full = t; else full = pp "/" t
      if (pp != "" && full != pp) isp[pp] = 1
      add(full, par)
      spath[++sp] = full; sind[sp] = w
    }
    END { for (i = 1; i <= cnt; i++) print (isp[order[i]] ? "P" : "F") "\t" order[i] }'
}

exists_branch() { exists_ref "refs/heads/$1" || exists_ref "refs/remotes/origin/$1"; }
has_branches_under() { [ -n "$(git for-each-ref --count=1 "refs/heads/$1/" "refs/remotes/origin/$1/")" ]; }

behind_note() { # ' (N behind <parent>: git subir)' when the branch lacks commits of its parent
	local b="$1" p pr br n
	p="$(parent_branch "$b")"
	[ -n "$p" ] || return 0
	pr="$(best_ref "$p" || true)"
	br="$(best_ref "$b" || true)"
	[ -n "$pr" ] && [ -n "$br" ] || return 0
	n="$(git rev-list --count "$br..$pr")"
	[ "$n" = 0 ] || printf ' (%s behind %s: git subir)' "$n" "$p"
}

cmd_estructura() {
	local dry=0 push=0 conv=0 files=() f a plan kind node b p base errs=0 why planned=$'\n' versions=""
	local topush=() n_new=0 n_ok=0
	for a in "$@"; do
		case "$a" in
		-n | --dry-run) dry=1 ;; --push) push=1 ;; --convertir) conv=1 ;;
		-*) die "unknown option '$a' (estructura: -n, --push, --convertir, --yes)" ;;
		*) files+=("$a") ;;
		esac
	done
	plan="$(mktemp)"
	# shellcheck disable=SC2064 # why: expanded now, 'plan' is local and gone when EXIT fires
	trap "rm -f '$plan'" EXIT
	if [ "${#files[@]}" -gt 0 ]; then
		for f in "${files[@]}"; do
			# why: git runs aliases from the top of the repository; GIT_PREFIX is where you were
			case "$f" in /* | [A-Za-z]:* | -) ;; *) f="${GIT_PREFIX:-}$f" ;; esac
			if [ "$f" = - ]; then cat; else
				[ -f "$f" ] || die "no such file: $f"
				cat "$f"
			fi
		done
	else
		[ -t 0 ] && echo "[rama] type the branch structure (one per line, indent for children), then Ctrl-D:" >&2
		cat
	fi | parse_structure >"$plan"
	[ -s "$plan" ] || die "no branches in the input"
	fetch_origin
	exists_branch "$QS_BR_MAINLINE" || die "'$QS_BR_MAINLINE' does not exist; create it first (git checkout -b $QS_BR_MAINLINE)"

	# pass 1: validate every name and conflict before touching anything
	while IFS=$'\t' read -r kind node <&3; do
		if [ "$kind" = P ]; then b="$node/$QS_BR_LEAF"; else b="$node"; fi
		# why: '<v>/<ot>/RELEASE' and '<F>/TESTING' are valid names, but only their commands create them
		if reserved_leaf_segment "${node##*/}"; then
			echo "  ! $b: '${node##*/}' is reserved ($QS_BR_LEAF, $QS_BR_RELEASE_LEAF, ${QS_BR_TESTING:-TESTING}, in any case)" >&2
			errs=$((errs + 1))
			continue
		fi
		if ! why="$(valid_branch_name "$b")"; then
			echo "  ! $b: $why" >&2
			errs=$((errs + 1))
			continue
		fi
		if [ "$kind" = P ] && ! exists_branch "$b" && exists_branch "$node" && [ "$conv" = 0 ]; then
			echo "  ! $b: '$node' is a final branch; it needs children, so make it a parent:" \
				"git estructura --convertir (or: git checkout $node && git convertir-padre)" >&2
			errs=$((errs + 1))
		fi
	done 3<"$plan"
	[ "$errs" = 0 ] || die "$errs problem(s) in the structure; nothing was created"

	# pass 2: ancestors first, so every new branch starts from its parent's tip
	while IFS=$'\t' read -r kind node <&3; do
		case " $versions " in *" ${node%%/*} "*) ;; *) versions="$versions ${node%%/*}" ;; esac
		if [ "$kind" = P ]; then b="$node/$QS_BR_LEAF"; else b="$node"; fi
		if exists_branch "$b"; then
			exists_ref "refs/remotes/origin/$b" || topush+=("$b")
			printf '  = %-48s exists%s%s\n' "$b" "$(exists_ref "refs/heads/$b" || echo ' (remote only)')" "$(behind_note "$b")"
			n_ok=$((n_ok + 1))
			continue
		fi
		if [ "$kind" = F ] && { exists_branch "$node/$QS_BR_LEAF" || has_branches_under "$node"; }; then
			printf '  = %-48s exists as a parent (%s)\n' "$b" "$node/$QS_BR_LEAF"
			n_ok=$((n_ok + 1))
			continue
		fi
		if [ "$kind" = P ] && exists_branch "$node"; then
			if [ "$dry" = 1 ]; then
				printf '  > %-48s would convert final %s\n' "$b" "$node"
			else
				convert_branch "$node"
				printf '  > %-48s converted from %s\n' "$b" "$node"
				exists_ref "refs/remotes/origin/$b" || topush+=("$b")
			fi
			planned="$planned$b"$'\n'
			n_new=$((n_new + 1))
			continue
		fi
		p="$(parent_branch "$b")"
		base="$(best_ref "$p" || true)"
		if [ -z "$base" ]; then
			case "$planned" in *$'\n'"$p"$'\n'*) base="$p" ;; *) die "parent '$p' of '$b' not found" ;; esac
		fi
		if [ "$dry" = 1 ]; then
			printf '  + %-48s would be created from %s\n' "$b" "$base"
		else
			git branch -q --no-track "$b" "$base"
			printf '  + %-48s created from %s\n' "$b" "$base"
			case "$node" in */*) ;; *) [ "$kind" = P ] && version_commit "$b" "$node" ;; esac
			topush+=("$b")
		fi
		planned="$planned$b"$'\n'
		n_new=$((n_new + 1))
	done 3<"$plan"

	if [ "$dry" = 1 ]; then
		say "dry run: $n_new to create, $n_ok existing; nothing was changed"
		return 0
	fi
	say "$n_new created, $n_ok already existing (current branch unchanged: $(current_branch || echo detached))"
	if [ "$push" = 1 ] && [ "${#topush[@]}" -gt 0 ]; then
		if has_origin; then
			say "pushing ${#topush[@]} branch(es) to origin..."
			git push -q -u origin "${topush[@]}"
		else say "no 'origin' remote: nothing pushed"; fi
	elif [ "${#topush[@]}" -gt 0 ]; then
		say "${#topush[@]} branch(es) of this structure are not on origin; share them with: git estructura --push"
	fi
	for a in $versions; do
		echo
		cmd_arbol "$a"
	done
}

# --- git changelog / git release / git publicar ------------------------------------------------
# A version tree '<version>/...' is released from its top '<version>/ORIGINAL', in two steps:
#   git release   every branch of the tree is compared with its nearest ORIGINAL (siblings with the
#                 ORIGINAL of their level, children with theirs, recursively); a branch with nothing
#                 outside it is integrated (deleted); a branch with commits that never reached it is
#                 set aside as 'unmerged/<name>' (with a warning). '<version>/ORIGINAL' becomes
#                 '<version>/RELEASE', which gets three commits: the version (VERSION, pom.xml),
#                 CHANGELOG.md (Common Changelog) and the README badge. The team reviews RELEASE.
#   git publicar  RELEASE is merged into develop, tagged, pushed and deleted.
# The changelog comes from the history of '<version>/ORIGINAL' (merge commits of 'git integra'
# carry 'Refs: <branch> -> <parent>'), so it works even after final branches were deleted.

all_branches() { # local and origin branch names, deduplicated
	{
		git for-each-ref --format='%(refname:lstrip=2)' refs/heads/
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | { grep -vx 'HEAD' || true; }
	} | LC_ALL=C sort -u
}
# the one tip of a branch: local and origin agree (one contains the other); 'diverged' otherwise
branch_tip() {
	local b="$1" l="" r=""
	exists_ref "refs/heads/$b" && l="$(git rev-parse "refs/heads/$b")"
	exists_ref "refs/remotes/origin/$b" && r="$(git rev-parse "refs/remotes/origin/$b")"
	if [ -n "$l" ] && [ -n "$r" ]; then
		if git merge-base --is-ancestor "$l" "$r"; then
			echo "$r"
		elif git merge-base --is-ancestor "$r" "$l"; then
			echo "$l"
		else echo diverged; fi
	else echo "${l:-$r}"; fi
}
# nearest existing ORIGINAL above a branch of the tree (its parent in the model, or higher up
# when that one is gone); the top of the tree for anything else
nearest_original() {
	local b="$1" p
	p="$(branch_node "$b")"
	is_parent_branch "$b" || p="$b"
	while case "$p" in */*) true ;; *) false ;; esac do
		p="${p%/*}"
		if [ "$p/$QS_BR_LEAF" != "$b" ] && exists_branch "$p/$QS_BR_LEAF"; then
			echo "$p/$QS_BR_LEAF"
			return
		fi
	done
	echo "$REL_TOP"
}
# a free name for a branch set aside: no ref with that name, under it, or above it (git stores
# refs as files and folders, so 'a/b' blocks 'a/b/c' and the other way round)
name_taken() {
	local n="$1" p="$1"
	exists_branch "$n" || has_branches_under "$n" && return 0
	while case "$p" in */*) true ;; *) false ;; esac do
		p="${p%/*}"
		exists_branch "$p" && return 0
	done
	case "$REL_PLANNED" in *$'\n'"$n"$'\n'*) return 0 ;; esac
	return 1
}
archive_name() {
	local base="$QS_BR_ARCHIVE/$1" n i
	n="$base"
	i=2
	while name_taken "$n" && [ "$i" -le 9 ]; do
		n="$base-$i"
		i=$((i + 1))
	done
	name_taken "$n" && n="$QS_BR_ARCHIVE-$(date +%Y%m%d%H%M%S)/$1"
	name_taken "$n" && return 1
	echo "$n"
}

# Markdown section of the history of <tip> not reachable from the excluded commits, following first
# parents; each merge becomes a sub-section with what it brought. Output on stdout.
#   cl_section <depth> <tip> <exclude>...
cl_section() {
	local depth="$1" tip="$2"
	shift 2
	local ex=() e H P h s an ad nm body src sub hd items="" subs="" line p1 p2
	for e in "$@"; do ex+=("^$e"); done
	while IFS=$'\x1f' read -r -d $'\x1e' H P h s an ad nm body; do
		H="${H#$'\n'}"
		[ -n "$H" ] || continue
		read -r p1 p2 _ <<<"$P"
		if [ -n "${p2:-}" ]; then
			src="$(sed -n 's/^Refs: \([^ ]*\) -> .*/\1/p' <<<"$body" | head -n1)"
			[ -n "$src" ] || src="$(sed -n "s/^Merge \(remote-tracking \)\{0,1\}branch '\(origin\/\)\{0,1\}\([^']*\)'.*/\3/p" <<<"$body" | head -n1)"
			[ -n "$src" ] || src="merge $h"
			sub="$(cl_section $((depth + 1)) "$p2" "$@" "$p1")"
			[ -n "$sub" ] || continue # a sync merge (parent into child): nothing new
			hd="$(printf '%*s' $((depth + 1)) '' | tr ' ' '#')"
			[ "$depth" -ge 5 ] && hd="######"
			subs="$subs"$'\n'"$hd $src"$'\n'"Integrated $ad by $an ($h): $s"$'\n'"$sub"$'\n'
		else
			src="$(sed -n 's/^Refs: \([^ ]*\) -> .*/\1/p' <<<"$body" | head -n1)"
			line="- $h $s ($an, $ad)${nm:+ [Norms: $nm]}"
			if [ -n "$src" ] && grep -q '^Commits:' <<<"$body"; then # squash integration
				hd="$(printf '%*s' $((depth + 1)) '' | tr ' ' '#')"
				subs="$subs"$'\n'"$hd $src (squashed)"$'\n'"Integrated $ad by $an ($h): $s"$'\n'
				subs="$subs$(sed -n '/^Commits:/,/^$/p' <<<"$body" | grep '^- ' || true)"$'\n'
			else
				items="$items$line"$'\n'
			fi
		fi
	done < <(git log --first-parent --reverse --date=short \
		--format='%H%x1f%P%x1f%h%x1f%s%x1f%an%x1f%ad%x1f%(trailers:key=Norms,valueonly,separator=%x2c)%x1f%B%x1e' \
		"$tip" ${ex[@]+"${ex[@]}"} --)
	if [ -n "$items" ]; then
		[ "$depth" = 1 ] && [ -n "$subs" ] && printf '## %s (direct commits)\n' "$REL_TOP"
		printf '%s' "$items"
	fi
	[ -n "$subs" ] && printf '%s' "$subs"
	return 0
}

# Analyse the tree of a version: fills REL_* variables, prints nothing.
release_analyse() {
	local v="$1" b p tb tp n
	REL_TOP="$v/$QS_BR_LEAF"
	REL_RELEASE="$v/$QS_BR_RELEASE_LEAF"
	REL_ERRORS=() REL_OK=() REL_ARCHIVE=() REL_DELETE_LOCAL=() REL_DELETE_REMOTE=() REL_PLANNED=$'\n'
	REL_TIP="" REL_BASE="" REL_CL_BASE="" REL_RESUME=0
	exists_branch "$REL_TOP" || {
		REL_ERRORS+=("'$REL_TOP' does not exist (git arbol $v)")
		return 0
	}
	REL_TIP="$(branch_tip "$REL_TOP")"
	[ "$REL_TIP" = diverged ] && REL_ERRORS+=("$REL_TOP: local and origin diverged; run git subir on it first")
	REL_BASE="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$REL_BASE" ] || REL_ERRORS+=("'$QS_BR_MAINLINE' does not exist")
	[ "$REL_TIP" = diverged ] || REL_CL_BASE="$REL_BASE"
	if exists_ref "refs/heads/$QS_BR_MAINLINE" && exists_ref "refs/remotes/origin/$QS_BR_MAINLINE" &&
		[ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ]; then
		REL_ERRORS+=("$QS_BR_MAINLINE: local and origin diverged; pull it first")
	fi
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		if git merge-base --is-ancestor "$REL_TIP" "$REL_BASE"; then
			REL_ERRORS+=("$REL_TOP is already inside $QS_BR_MAINLINE (integrated with git integra?): nothing to release")
		elif ! git merge-base --is-ancestor "$REL_BASE" "$REL_TIP"; then
			REL_ERRORS+=("$QS_BR_MAINLINE has $(git rev-list --count "$REL_TIP..$REL_BASE") commit(s) that $REL_TOP lacks; bring them in first: git checkout $REL_TOP && git subir")
		fi
	fi
	if exists_branch "$REL_RELEASE" && [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		local rt
		rt="$(branch_tip "$REL_RELEASE")"
		if [ "$rt" != diverged ] && git merge-base --is-ancestor "$REL_TIP" "$rt"; then
			REL_RESUME=1 # an interrupted git release: go on from there
		else
			REL_ERRORS+=("'$REL_RELEASE' exists and does not contain $REL_TOP (left by an earlier release?); publish or delete it first")
		fi
	fi
	# every branch of the tree against its nearest ORIGINAL
	while IFS= read -r b; do
		[ -n "$b" ] && [ "$b" != "$REL_TOP" ] && [ "$b" != "$REL_RELEASE" ] || continue
		tb="$(branch_tip "$b")"
		p="$(nearest_original "$b")"
		tp="$(branch_tip "$p")"
		if [ "$tb" = diverged ] || [ "$tp" = diverged ]; then
			REL_ERRORS+=("$([ "$tb" = diverged ] && echo "$b" || echo "$p"): local and origin diverged; run git subir on it first")
			continue
		fi
		n="$(git rev-list --count "$tp..$tb")"
		if [ "$n" = 0 ]; then
			REL_OK+=("$b"$'\t'"$p")
		else
			local new
			new="$(archive_name "$b")" || {
				REL_ERRORS+=("no free name to set '$b' aside")
				continue
			}
			REL_PLANNED="$REL_PLANNED$new"$'\n'
			REL_ARCHIVE+=("$b"$'\t'"$new"$'\t'"$p"$'\t'"$n")
		fi
	done < <(all_branches | awk -v p="$v/" 'index($0, p) == 1')
	# the branches to delete afterwards: the integrated ones, the old names of those set aside, the top
	local entry archived=$'\n'
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do archived="$archived${entry%%$'\t'*}"$'\n'; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"} "$REL_TOP"$'\t' ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		b="${entry%%$'\t'*}"
		exists_ref "refs/remotes/origin/$b" && REL_DELETE_REMOTE+=("$b")
		case "$archived" in *$'\n'"$b"$'\n'*) continue ;; esac # set aside: renamed locally instead
		exists_ref "refs/heads/$b" && REL_DELETE_LOCAL+=("$b")
	done
	# branches of the tree checked out in another worktree cannot be deleted from here
	local here wt
	here="$(git rev-parse --show-toplevel)"
	while IFS= read -r wt; do
		b="${wt#*$'\t'}"
		b="${b#refs/heads/}"
		case "$b" in "$v"/* | "$QS_BR_MAINLINE") REL_ERRORS+=("'$b' is checked out in another worktree; switch it or remove that worktree") ;; esac
	done < <(git worktree list --porcelain | awk -v h="$here" '/^worktree /{w=substr($0,10)} /^branch /{ if (w != h) print w "\t" $2 }')
	return 0
}

release_changelog() { # <tag> -> markdown on stdout: what each branch brought (for the review)
	local tag="$1" b p n entry
	echo "# Release $tag"
	echo
	echo "From \`$REL_TOP\` ($(git rev-parse --short "$REL_TIP")) into \`$QS_BR_MAINLINE\`" \
		"($(git rev-parse --short "$REL_CL_BASE")): $(git rev-list --count --no-merges "$REL_TIP" "^$REL_CL_BASE") commit(s)."
	echo
	cl_section 1 "$REL_TIP" "$REL_CL_BASE" | sed '1{/^$/d}'
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo
		echo "## Not included: never integrated into their ORIGINAL"
		for entry in "${REL_ARCHIVE[@]}"; do
			IFS=$'\t' read -r b n p _ <<<"$entry"
			echo
			echo "### $b -> set aside as $n"
			git log --no-merges --date=short --format='- %h %s (%an, %ad)' "$(branch_tip "$p")..$(branch_tip "$b")"
		done
	fi
}

# The CHANGELOG.md entry of the release (Common Changelog), from the suite image; semver advice on stderr.
release_notes() { # release_notes [--write]
	local root
	root="$(git rev-parse --show-toplevel)"
	engine "$root" release-notes --version "$REL_VERSION" --tip "$REL_TIP" --base "$REL_CL_BASE" --tag "$REL_TAG" "$@"
}

release_report() { # <tag>: checks and plan, for the preview and before running
	local tag="$1" entry b p n new e
	echo "## Checks"
	echo
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then echo "[ok] $REL_TOP is consistent (local/origin) and contains $QS_BR_MAINLINE"; fi
	for e in ${REL_ERRORS[@]+"${REL_ERRORS[@]}"}; do echo "[!!] $e"; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"}; do
		IFS=$'\t' read -r b p <<<"$entry"
		echo "[ok] $b: contained in $p"
	done
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new p n <<<"$entry"
		echo "[!!] $b: $n commit(s) not in $p -> will be set aside as $new"
	done
	[ "$REL_RESUME" = 1 ] && echo "[ok] $REL_RELEASE exists and contains $REL_TOP: git release resumes from there"
	echo
	echo "## Plan"
	echo
	local i=1
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo "$i. set aside ${#REL_ARCHIVE[@]} branch(es) as $QS_BR_ARCHIVE/... (local and origin)"
		i=$((i + 1))
	fi
	echo "$i. git release: $REL_TOP -> $REL_RELEASE, with up to three commits: $(version_subject "$REL_VERSION")," \
		"docs(changelog): $REL_VERSION ($QS_BR_CHANGELOG), docs(readme): version $REL_VERSION"
	i=$((i + 1))
	echo "$i. git release: push $REL_RELEASE; delete the rest of the tree: ${#REL_DELETE_LOCAL[@]} local branch(es)$(has_origin && [ "$REL_PUSH" = 1 ] && echo ", ${#REL_DELETE_REMOTE[@]} on origin")"
	i=$((i + 1))
	echo "$i. you: review $QS_BR_CHANGELOG on $REL_RELEASE (edit and commit there if needed)"
	i=$((i + 1))
	echo "$i. git publicar: $REL_RELEASE merged into $QS_BR_MAINLINE (\"$(release_subject "$tag")\"), tag $tag, push, $REL_RELEASE deleted"
}

release_subject() {
	local s="chore(release): $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: release $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: $1"
	printf '%s' "$s"
}

# release_args <argument>...: read the options of git changelog / release / publicar.
# Sets REL_TAG REL_TAG_GIVEN REL_VERSION REL_OT REL_OUT REL_PUSH REL_PREVIEW REL_TAG_AT. REL_OT
# ('<v>/<ot>', flow = squash only) comes from --ot or, without --version, from a current branch
# inside an OT ('<v>/<ot>/...'); empty means the version release.
# Returns: 0; exits through die on a bad option, version, OT or tag.
release_args() {
	REL_TAG="" REL_TAG_GIVEN=0 REL_VERSION="" REL_OT="" REL_OUT="" REL_PUSH=1 REL_PREVIEW=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--version)
			REL_VERSION="${2:?--version needs a version}"
			shift
			;;
		--version=*) REL_VERSION="${1#--version=}" ;;
		--ot)
			REL_OT="${2:?--ot needs <version>/<ot>}"
			shift
			;;
		--ot=*) REL_OT="${1#--ot=}" ;;
		-o | --output)
			REL_OUT="${2:?$1 needs a file}"
			shift
			;;
		--no-push) REL_PUSH=0 ;;
		-n | --preview) REL_PREVIEW=1 ;;
		-*) die "unknown option '$1'" ;;
		*)
			[ -z "$REL_TAG" ] || die "one tag only (got '$REL_TAG' and '$1')"
			REL_TAG="$1"
			REL_TAG_GIVEN=1
			;;
		esac
		shift
	done
	ot_release_target
	if [ -z "$REL_VERSION" ]; then
		local cur
		cur="$(current_branch || true)"
		if [ -n "$cur" ] && ! is_mainline "$cur" && ! is_archived_branch "$cur" && valid_branch_name "$cur" >/dev/null 2>&1; then
			REL_VERSION="$(branch_version "$cur")"
		else
			local tops
			tops="$(all_branches | awk -v l="/$QS_BR_LEAF" -v r="/$QS_BR_RELEASE_LEAF" '(gsub(l "$", "") || gsub(r "$", "")) && index($0, "/") == 0' | sort -u)"
			[ "$(grep -c . <<<"$tops")" = 1 ] && REL_VERSION="$tops"
			[ -n "$REL_VERSION" ] || die "which version? add --version <version> (version trees: ${tops//$'\n'/ })"
		fi
	fi
	REL_VERSION="${REL_VERSION%%/*}"
	printf '%s' "$REL_VERSION" | grep -qE -- "$(_br_level_re 1)" || die "'$REL_VERSION' is not a version of the branch model (branches.levels[0])"
	# why: git release keeps the tag it was given for git publicar (and the changelog link)
	[ -n "$REL_TAG" ] || REL_TAG="$(git config "qs.release.$REL_VERSION.tag" 2>/dev/null || true)"
	[ -n "$REL_TAG" ] || REL_TAG="$(render_tag "$REL_VERSION/$QS_BR_LEAF")"
	git check-ref-format "refs/tags/$REL_TAG" || die "'$REL_TAG' is not a valid tag name"
	LC_ALL=C grep -q '[^ -~]' <<<"$REL_TAG" && die "the tag must be ASCII: '$REL_TAG'"
	if exists_ref "refs/tags/$REL_TAG"; then REL_TAG_AT="$(git rev-parse "refs/tags/$REL_TAG^{commit}")"; else REL_TAG_AT=""; fi
	return 0
}

cmd_changelog() { # preview: changelog + release notes + checks + plan; changes nothing
	release_args "$@"
	if [ -n "$REL_OT" ]; then
		ot_changelog_preview
		return
	fi
	fetch_origin
	if ! exists_branch "$REL_VERSION/$QS_BR_LEAF" && exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF"; then
		say "$REL_VERSION is prepared on $REL_VERSION/$QS_BR_RELEASE_LEAF (git release done): review it, then git publicar"
		return 0
	fi
	release_analyse "$REL_VERSION"
	[ -n "$REL_TAG_AT" ] && [ "${#REL_ERRORS[@]}" -eq 0 ] && [ "$REL_TAG_AT" != "$REL_TIP" ] &&
		REL_ERRORS+=("tag '$REL_TAG' already exists on another commit; choose another name")
	if [ -n "$REL_TIP" ] && [ "$REL_TIP" != diverged ] && [ -n "$REL_CL_BASE" ]; then
		release_changelog "$REL_TAG"
		echo
		if [ -n "$REL_OUT" ]; then
			case "$REL_OUT" in /* | [A-Za-z]:*) ;; *) REL_OUT="${GIT_PREFIX:-}$REL_OUT" ;; esac
			release_changelog "$REL_TAG" >"$REL_OUT"
			say "changelog written to $REL_OUT"
		fi
		echo "## $QS_BR_CHANGELOG entry (Common Changelog)"
		echo
		release_notes 2>&1 || echo "(the suite image could not run: no release notes preview)"
		echo
	fi
	release_report "$REL_TAG"
	[ "${#REL_ERRORS[@]}" -eq 0 ] || {
		echo
		say "not releasable yet: fix the [!!] items above"
		return 1
	}
	echo
	say "preview only, nothing changed. Next: git release $REL_TAG --version $REL_VERSION"
}

# What to tell the human when a release commit fails: git release resumes, git combinar starts over.
REL_AGAIN="fix it, then run the same git release again (it resumes)"

# commit_files <subject> <file>...: commit those files if they changed (the hooks run).
# Arguments: $1 the subject; $2... the files (missing ones are skipped). Exit status: 0; ends the
# script through die when a hook rejects the commit (the message ends with REL_AGAIN).
commit_files() {
	local subject="$1"
	shift
	local f add=()
	for f in "$@"; do [ -n "$f" ] && [ -e "$f" ] && add+=("$f"); done
	[ "${#add[@]}" -gt 0 ] || return 0
	git add -- "${add[@]}"
	git diff --cached --quiet && return 0
	git commit -q -m "$subject" || die "the commit '$subject' was rejected (see the hook messages); $REL_AGAIN"
	say "committed: $subject"
}

cmd_release() { # step 1: RELEASE branch with version, changelog and README badge; tree deleted
	local root
	release_args "$@"
	[ "$REL_PREVIEW" = 1 ] && {
		cmd_changelog "$@"
		return
	}
	if [ -n "$REL_OT" ]; then
		ot_release
		return
	fi
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	if ! exists_branch "$REL_VERSION/$QS_BR_LEAF" && exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF"; then
		say "$REL_VERSION/$QS_BR_RELEASE_LEAF is already prepared. Review $QS_BR_CHANGELOG there, then: git publicar --version $REL_VERSION"
		return 0
	fi
	release_analyse "$REL_VERSION"
	[ -n "$REL_TAG_AT" ] && [ "${#REL_ERRORS[@]}" -eq 0 ] && [ "$REL_TAG_AT" != "$REL_TIP" ] &&
		REL_ERRORS+=("tag '$REL_TAG' already exists on another commit; choose another name")
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		release_report "$REL_TAG" >&2
		die "nothing was changed"
	fi
	release_changelog "$REL_TAG"
	echo
	echo "## $QS_BR_CHANGELOG entry (Common Changelog)"
	echo
	release_notes 2>&1 || die "the suite image could not run (Docker?): it writes $QS_BR_CHANGELOG; nothing was changed"
	echo
	release_report "$REL_TAG"
	echo
	confirm "Prepare $REL_VERSION on $REL_RELEASE?" || die "cancelled; nothing was changed"
	git config "qs.release.$REL_VERSION.tag" "$REL_TAG"
	root="$(git rev-parse --show-toplevel)"

	# 1. RELEASE at the tip of the version ORIGINAL (kept until the end: a failure leaves the tree)
	exists_ref "refs/heads/$REL_RELEASE" || git branch -q --no-track "$REL_RELEASE" "$([ "$REL_RESUME" = 1 ] && branch_tip "$REL_RELEASE" || echo "$REL_TIP")"
	git checkout -q "$REL_RELEASE"
	# 2.-4. the version (a SNAPSHOT pom becomes the release version), CHANGELOG.md, the README badge
	release_commits
	# 5. publish RELEASE before touching any remote branch
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		git push -q -u origin "$REL_RELEASE" || die "push of $REL_RELEASE failed; the tree is untouched. Fix it and run git release again (it resumes)"
	fi
	# 6. branches never integrated: set aside as unmerged/<name>
	release_set_aside
	# 7. the rest of the tree (integrated branches, old names, the ORIGINAL)
	if [ "$REL_PUSH" = 1 ] && has_origin && [ "${#REL_DELETE_REMOTE[@]}" -gt 0 ]; then
		git push -q origin --delete "${REL_DELETE_REMOTE[@]}"
	fi
	[ "${#REL_DELETE_LOCAL[@]}" -gt 0 ] && git branch -q -D "${REL_DELETE_LOCAL[@]}"
	say "$REL_VERSION prepared on $REL_RELEASE: ${#REL_DELETE_LOCAL[@]} branch(es) of the tree deleted, ${#REL_ARCHIVE[@]} set aside"
	echo
	echo "Review now (you are on $REL_RELEASE):"
	echo "  git show --stat HEAD~2..HEAD          # the release commits"
	echo "  \$EDITOR $QS_BR_CHANGELOG               # wording, order; then: git commit -am 'docs(changelog): review'"
	echo "When it is right:"
	echo "  git publicar                          # merge into $QS_BR_MAINLINE, tag $REL_TAG, push, delete $REL_RELEASE"
	return 0
}

cmd_publicar() { # step 2: RELEASE merged into develop, tagged, pushed, deleted
	local tip base notes msg pushed=0 merged=0 root rels
	# why: with several RELEASE branches, which one reaches develop is said explicitly, one at a time
	rels="$(release_branches)"
	if [ "$(grep -c . <<<"$rels")" -gt 1 ] && ! printf ' %s' "$@" | grep -qE ' --version(=| )'; then
		die "there are $(grep -c . <<<"$rels") RELEASE branches (${rels//$'\n'/ }); publish one at a time: git publicar --version <v>  (or join them first: git combinar)"
	fi
	release_args "$@"
	REL_RELEASE="$REL_VERSION/$QS_BR_RELEASE_LEAF"
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	exists_branch "$REL_RELEASE" || die "'$REL_RELEASE' does not exist: prepare it first with git release --version $REL_VERSION"
	tip="$(branch_tip "$REL_RELEASE")"
	[ "$tip" = diverged ] && die "$REL_RELEASE: local and origin diverged; pull it first (git checkout $REL_RELEASE && git pull)"
	base="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$base" ] || die "'$QS_BR_MAINLINE' does not exist"
	[ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ] && die "$QS_BR_MAINLINE: local and origin diverged; pull it first"
	if git merge-base --is-ancestor "$tip" "$base"; then
		merged=1 # resumed after the merge
	elif ! git merge-base --is-ancestor "$base" "$tip"; then
		die "$QS_BR_MAINLINE has $(git rev-list --count "$tip..$base") commit(s) that $REL_RELEASE lacks: git checkout $REL_RELEASE && git merge $QS_BR_MAINLINE, review again, then git publicar"
	fi
	[ -n "$REL_TAG_AT" ] && [ "$REL_TAG_AT" != "$tip" ] && die "tag '$REL_TAG' already exists on another commit; give another: git publicar <tag>"
	root="$(git rev-parse --show-toplevel)"
	notes="$(git rev-parse --absolute-git-dir)/quality-suite/RELEASE_NOTES.md"
	mkdir -p "$(dirname "$notes")"
	{
		echo "Release $REL_TAG ($REL_VERSION)"
		echo
		if [ -n "$QS_BR_CHANGELOG" ] && git cat-file -e "$tip:$QS_BR_CHANGELOG" 2>/dev/null; then
			git show "$tip:$QS_BR_CHANGELOG" | awk -v v="$REL_VERSION" '
        /^## / { if (on) exit; on = (index($0, "## [" v "]") == 1 || index($0, "## " v " ") == 1); next }
        on { print }' | sed '/./,$!d'
		fi
	} >"$notes"
	[ "$(grep -c . "$notes")" -gt 1 ] || echo "[rama] WARN: $QS_BR_CHANGELOG on $REL_RELEASE has no entry for $REL_VERSION" >&2
	cat "$notes"
	echo
	echo "Plan: $REL_RELEASE -> $QS_BR_MAINLINE (\"$(release_subject "$REL_TAG")\"), tag $REL_TAG$([ "$REL_PUSH" = 1 ] && has_origin && echo ", push $QS_BR_MAINLINE and $REL_TAG"), delete $REL_RELEASE"
	confirm "Publish $REL_VERSION as $REL_TAG?" || die "cancelled; nothing was changed"

	if exists_ref "refs/heads/$QS_BR_MAINLINE"; then
		git checkout -q "$QS_BR_MAINLINE"
	else git checkout -q -b "$QS_BR_MAINLINE" --track "origin/$QS_BR_MAINLINE"; fi
	[ "$(git rev-parse HEAD)" = "$(git rev-parse "$base")" ] || git merge -q --ff-only "$base"
	if [ "$merged" = 0 ]; then
		msg="$(git rev-parse --absolute-git-dir)/quality-suite/RELEASE_MSG"
		{
			release_subject "$REL_TAG"
			echo
			echo
			echo "Release $REL_TAG of $REL_VERSION: $(git rev-list --count --no-merges "$tip" "^$base") commit(s)."
			echo "Refs: $REL_RELEASE -> $QS_BR_MAINLINE"
		} >"$msg"
		exists_ref "refs/heads/$REL_RELEASE" || git branch -q --no-track "$REL_RELEASE" "$tip"
		quiet_merge merge -q --no-ff --no-commit "$REL_RELEASE" ||
			{
				git merge --abort 2>/dev/null || true
				die "merge into $QS_BR_MAINLINE failed; nothing was changed"
			}
		if ! git commit -q --cleanup=strip -F "$msg"; then
			git merge --abort 2>/dev/null || true
			die "the merge commit was rejected (see the hook messages above); nothing was changed"
		fi
		say "$REL_RELEASE merged into $QS_BR_MAINLINE"
	fi
	if [ -z "$REL_TAG_AT" ]; then
		git tag -a --cleanup=whitespace -F "$notes" "$REL_TAG" "$tip"
		say "tag $REL_TAG created on $REL_RELEASE"
	fi
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		git push -q origin "$QS_BR_MAINLINE" "refs/tags/$REL_TAG" ||
			die "push failed: $QS_BR_MAINLINE and $REL_TAG are ready locally and $REL_RELEASE is kept. Fix the push and run git publicar again (it resumes)"
		pushed=1
		say "pushed $QS_BR_MAINLINE and $REL_TAG"
		exists_ref "refs/remotes/origin/$REL_RELEASE" && git push -q origin --delete "$REL_RELEASE"
	fi
	exists_ref "refs/heads/$REL_RELEASE" && git branch -q -D "$REL_RELEASE"
	git config --unset "qs.release.$REL_VERSION.tag" 2>/dev/null || true
	say "published $REL_VERSION as $REL_TAG; $REL_RELEASE deleted"
	[ "$pushed" = 1 ] || { has_origin && say "not pushed (--no-push): git push origin $QS_BR_MAINLINE $REL_TAG && git push origin --delete $REL_RELEASE"; }
	return 0
}

# --- git nueva-version / git combinar ----------------------------------------------------------
# sync_branch <branch> <parent>: bring the parent into the branch with a merge commit made without
# a work tree (git merge-tree); 1 when they conflict (the branch is left as it was)
sync_branch() {
	local b="$1" p="$2" bt pt tree commit
	bt="$(git rev-parse "refs/heads/$b")"
	pt="$(git rev-parse "refs/heads/$p")"
	git merge-base --is-ancestor "$pt" "$bt" && return 0
	# why: a copy with nothing of its own (already integrated) just moves to its parent: a merge
	# commit would make it look unintegrated
	if git merge-base --is-ancestor "$bt" "$pt"; then
		git update-ref "refs/heads/$b" "$pt" "$bt"
		return 0
	fi
	tree="$(git merge-tree --write-tree "$bt" "$pt" 2>/dev/null)" || return 1
	tree="$(head -n1 <<<"$tree")"
	commit="$(git commit-tree "$tree" -p "$bt" -p "$pt" -m "Merge branch '$p' into $b")"
	git update-ref "refs/heads/$b" "$commit" "$bt"
}

cmd_nueva_version() {
	local v="" src="$FROM" dry=0 full=0 a node srcv b nb rel why left=() made=() n plan p pre seg i
	for a in "$@"; do
		case "$a" in -n | --dry-run) dry=1 ;; --arbol-completo | --full) full=1 ;;
		-*) die "unknown option '$a' (nueva-version: --from <branch>, --arbol-completo, -n)" ;;
		*)
			[ -z "$v" ] || die "one version only (got '$v' and '$a')"
			v="$a"
			;;
		esac
	done
	[ -n "$v" ] || die "usage: git nueva-version <version> [--from <branch>]   e.g. git nv 6.22.6-SNAPSHOT --from 6.22.6/188858/ORIGINAL"
	fetch_origin
	case "$v" in major | minor | patch)
		v="$(next_version "$v")"
		say "next version: $v"
		;;
	esac
	[ -n "$src" ] || src="$(current_branch)" || die "detached HEAD: add --from <branch>"
	exists_branch "$src" || die "branch '$src' not found"
	why="$(valid_branch_name "$v/$QS_BR_LEAF")" || die "invalid version '$v': $why"
	taken "$v" && die "'$v' already exists (as a branch or a version tree)"
	# the copies keep their path below the version ('6.22.6/188858/login' -> '<v>/188858/login'):
	# the branches below the chosen one, the parents between the version and it, or (--arbol-completo)
	# the whole tree of its version
	plan="$(mktemp)"
	# shellcheck disable=SC2064 # why: expanded now, 'plan' is local and gone when EXIT fires
	trap "rm -f '$plan'" EXIT
	srcv=""
	node=""
	if ! is_mainline "$src" && ! is_archived_branch "$src" && valid_branch_name "$src" >/dev/null 2>&1; then
		srcv="$(branch_version "$src")"
		is_parent_branch "$src" && node="$(branch_node "$src")"
	fi
	{
		printf 'R\t%s/%s\t%s\n' "$v" "$QS_BR_LEAF" "$src"
		if [ -n "$srcv" ] && [ "$full" = 1 ]; then
			all_branches | awk -v p="$srcv/" -v t="$srcv/$QS_BR_LEAF" -v r="$srcv/$QS_BR_RELEASE_LEAF" \
				'index($0, p) == 1 && $0 != t && $0 != r { print "C\t" $0 }'
		elif [ -n "$node" ] && [ "$node" != "$srcv" ]; then
			rel="${node#"$srcv"/}"
			pre=""
			i=0
			while IFS= read -r seg; do # the parents between the version and the chosen one
				pre="${pre:+$pre/}$seg"
				if [ "$pre" = "$rel" ]; then
					printf 'S\t%s/%s/%s\t%s\n' "$v" "$pre" "$QS_BR_LEAF" "$src"
				else printf 'P\t%s/%s/%s\t-\n' "$v" "$pre" "$QS_BR_LEAF"; fi
			done < <(tr '/' '\n' <<<"$rel")
			all_branches | awk -v p="$node/" -v me="$src" 'index($0, p) == 1 && $0 != me { print "C\t" $0 }'
		elif [ -n "$node" ]; then
			all_branches | awk -v p="$node/" -v me="$src" -v r="$srcv/$QS_BR_RELEASE_LEAF" \
				'index($0, p) == 1 && $0 != me && $0 != r { print "C\t" $0 }'
		fi
	} | awk -F'\t' -v v="$v" -v sv="$srcv" '
      $1 == "C" { rest = substr($2, length(sv) + 2); print $1 "\t" v "/" rest "\t" $2; next }
      { print }' | awk -F'\t' -v leaf="$QS_BR_LEAF" '{ n = split($2, a, "/"); if (a[n] == leaf) n--; print n "\t" $0 }' |
		sort -s -n -k1,1 | cut -f2- >"$plan" # why: by node depth, so every parent exists before its children
	while IFS=$'\t' read -r a nb b; do
		why="$(valid_branch_name "$nb")" || die "'$nb' is not a valid name: $why"
		case "$a" in R) echo "  + $nb   from $b (version commit: $v)" ;; P) echo "  + $nb   new parent" ;;
		*) echo "  + $nb   copy of $b" ;; esac
	done <"$plan"
	[ "$dry" = 1 ] && {
		say "dry run: nothing was created"
		return 0
	}
	while IFS=$'\t' read -r a nb b; do
		case "$a" in
		R)
			git branch -q --no-track "$nb" "$(best_ref "$b")"
			version_commit "$nb" "$v"
			;;
		P) git branch -q --no-track "$nb" "$(parent_branch "$nb")" ;;
		*)
			git branch -q --no-track "$nb" "$(best_ref "$b")"
			sync_branch "$nb" "$(parent_branch "$nb")" || left+=("$nb")
			;;
		esac
		made+=("$nb")
	done <"$plan"
	say "version tree $v created from $src: ${#made[@]} branch(es), next to the others (git arbol $v)"
	for n in ${left[@]+"${left[@]}"}; do
		echo "[rama] WARN: $n conflicts with its new parent; bring it up to date by hand: git checkout $n && git subir" >&2
	done
	has_origin && say "share it: git push -u origin ${made[*]}"
	return 0
}

release_branches() { # every '<version>/RELEASE' (local or origin)
	local b
	while IFS= read -r b; do is_release_branch "$b" && printf '%s\n' "$b"; done < <(all_branches)
	return 0
}

RELEASE_COMMITS_RX='^(chore\((version|release)\)|docs\((changelog|readme)\))[:!]'

# release_commits: the release commits of REL_VERSION on the HEAD of the current work tree
# (REL_RELEASE, or the temporary worktree of git combinar): version files, CHANGELOG.md entry,
# README badge.
# Arguments: none; reads REL_VERSION REL_TIP REL_CL_BASE REL_TAG REL_AGAIN. Exit status: 0; ends
# the script through die when the suite image cannot run or a hook rejects a commit.
release_commits() {
	local root changed pom
	root="$(git rev-parse --show-toplevel)"
	pom="$QS_BR_POM"
	[ "$pom" = snapshot ] && pom=update
	changed="$(engine "$root" version-set "$REL_VERSION" --pom "$pom" --version-file "$QS_BR_VERSION_FILE" | tr -d '\r')" ||
		die "the suite image could not run (Docker?); $REL_AGAIN"
	# shellcheck disable=SC2086
	[ -z "$changed" ] || commit_files "$(version_subject "$REL_VERSION")" $changed
	if [ -n "$QS_BR_CHANGELOG" ]; then
		release_notes --write >/dev/null 2>&1 || die "could not write $QS_BR_CHANGELOG; $REL_AGAIN"
		commit_files "docs(changelog): $REL_VERSION" "$QS_BR_CHANGELOG"
	fi
	changed="$(engine "$root" release-docs --version "$REL_VERSION" | tr -d '\r')" || die "could not update the README badge; $REL_AGAIN"
	# shellcheck disable=SC2086
	[ -z "$changed" ] || commit_files "docs(readme): version $REL_VERSION" $changed
}

# aside_existing <branch>: the name under which <branch> was already set aside, when a local
# 'unmerged/<branch>' (or its '-N' / stamped variant) points at the same commit as the branch
# (its local or origin ref): the mark of a release that failed after setting it aside (AC O6).
# Arguments: $1 branch. Returns: 0 and prints that name; 1 when there is none.
aside_existing() {
	local b="$1" sha ref name
	if exists_ref "refs/heads/$b"; then
		sha="$(git rev-parse "refs/heads/$b")"
	elif exists_ref "refs/remotes/origin/$b"; then
		sha="$(git rev-parse "refs/remotes/origin/$b")"
	else return 1; fi
	while IFS=' ' read -r ref name; do
		case "$name" in
		"$QS_BR_ARCHIVE/$b" | "$QS_BR_ARCHIVE/$b"-[0-9] | "$QS_BR_ARCHIVE"-*/"$b") ;;
		*) continue ;;
		esac
		[ "$ref" = "$sha" ] || continue
		printf '%s\n' "$name"
		return 0
	done < <(git for-each-ref --format='%(objectname) %(refname:short)' refs/heads)
	return 1
}

# release_set_aside: set every REL_ARCHIVE branch aside under its 'unmerged/...' name: renamed
# locally (or a local copy of a branch only on origin) and copied on origin when REL_PUSH is 1
# and there is an origin; one warning per branch on stderr.
# Arguments: none; reads REL_ARCHIVE ("<branch><TAB><new name><TAB><ORIGINAL><TAB><commits>").
# Returns: 0; a failed git command ends the script (set -e).
release_set_aside() {
	local entry b new p n done_as
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new p n <<<"$entry"
		if done_as="$(aside_existing "$b")"; then
			# a failed earlier run already set it aside: do not copy it again
			if [ "$REL_PUSH" = 1 ] && has_origin && ! exists_ref "refs/remotes/origin/$done_as"; then
				git push -q origin "refs/heads/$done_as:refs/heads/$done_as"
			fi
			continue
		fi
		if exists_ref "refs/heads/$b"; then
			git branch -m "$b" "$new"
		else git branch -q --no-track "$new" "origin/$b"; fi # remote only: keep a local copy too
		if [ "$REL_PUSH" = 1 ] && has_origin && exists_ref "refs/remotes/origin/$b"; then git push -q origin "refs/remotes/origin/$b:refs/heads/$new"; fi
		echo "[rama] WARN: $b had $n commit(s) not in $p: set aside as $new" >&2
	done
	return 0
}

# --- OT release (flow = squash): '<v>/<ot>/ORIGINAL' -> '<v>/<ot>/RELEASE' ---------------------
# git release inside '<v>/<ot>/...' (or --ot <v>/<ot>): RELEASE at the OT ORIGINAL tip plus one
# docs(changelog) commit with the OT lines of the '## <v>' section, the annotated tag
# branches.ot_tag on the OT ORIGINAL tip (keeps the cited hashes reachable), one push of RELEASE
# and the tag, then the OT subtree deleted (the OT ORIGINAL last: while it exists the release is
# not finished and running it again resumes). VERSION and the README badge are not touched: the
# version release ('git release --version <v>') does that once every OT has its RELEASE.

# ot_release_target: settle REL_OT once release_args has read the options. --ot is refused with
# branches.flow = merge, normalised to '<v>/<ot>' and checked against the model and --version.
# Without --ot and --version (flow = squash), a current branch inside an OT ('<v>/<ot>/...', three
# or more segments) selects that OT.
# Arguments: none; reads and sets REL_OT and REL_VERSION. Returns: 0; exits through die on a bad --ot.
ot_release_target() {
	local cur v o
	if [ -n "$REL_OT" ]; then
		[ "${QS_BR_FLOW:-merge}" = squash ] ||
			die "--ot needs branches.flow = squash; this repository keeps the 4.x merge flow (git release --version <v>)"
		REL_OT="${REL_OT%/}"
		REL_OT="${REL_OT%/"$QS_BR_LEAF"}"
		case "$REL_OT" in */*/* | /* | */) die "--ot takes <version>/<ot>, e.g. 9.0.0/500 (got '$REL_OT')" ;; */*) ;; *) die "--ot takes <version>/<ot>, e.g. 9.0.0/500 (got '$REL_OT')" ;; esac
		v="${REL_OT%%/*}" o="${REL_OT#*/}"
		if ! printf '%s' "$v" | grep -qE -- "$(_br_level_re 1)" || ! printf '%s' "$o" | grep -qE -- "$(_br_level_re 2)" ||
			reserved_leaf_segment "$o"; then
			die "'$REL_OT' is not <version>/<ot> of the branch model (branches.levels)"
		fi
		[ -z "$REL_VERSION" ] || [ "${REL_VERSION%%/*}" = "$v" ] || die "--ot $REL_OT is not in --version $REL_VERSION"
		REL_VERSION="$v"
	elif [ -z "$REL_VERSION" ] && [ "${QS_BR_FLOW:-merge}" = squash ]; then
		cur="$(current_branch || true)"
		case "$cur" in */*/*) ;; *) return 0 ;; esac
		is_archived_branch "$cur" && return 0
		valid_branch_name "$cur" >/dev/null 2>&1 || return 0
		REL_OT="$(cut -d/ -f1-2 <<<"$cur")"
	fi
	return 0
}

# render_ot_tag <v>/<ot>: the tag of an OT release from branches.ot_tag ({version}, {ot}, {date}).
# Arguments: $1 '<v>/<ot>'. Returns: 0; prints the tag (nothing when ot_tag is '').
render_ot_tag() {
	local t="$QS_BR_OT_TAG"
	[ -n "$t" ] || return 0
	t="${t//\{version\}/${1%%/*}}"
	t="${t//\{ot\}/${1#*/}}"
	t="${t//\{date\}/$(date +%Y%m%d)}"
	printf '%s' "$t"
}

# ot_release_branches <v>: hook for the version release: every '<v>/<ot>/RELEASE' of a version,
# local or on origin, one per line, sorted.
# Arguments: $1 version. Returns: 0.
ot_release_branches() {
	local b
	while IFS= read -r b; do
		is_ot_release_branch "$b" && [ "${b%%/*}" = "$1" ] && printf '%s\n' "$b"
	done < <(all_branches)
	return 0
}

# version_ots <v>: hook for the version release: the OTs of a version, i.e. the folders '<v>/<ot>/'
# holding any branch (local or on origin), one per line, sorted; reserved leaves are not OTs.
# Arguments: $1 version. Returns: 0.
version_ots() {
	local o
	while IFS= read -r o; do
		[ -n "$o" ] && ! reserved_leaf_segment "$o" && printf '%s\n' "$o"
	done < <(all_branches | awk -F/ -v v="$1" '$1 == v && NF >= 3 { print $2 }' | LC_ALL=C sort -u)
	return 0
}

# ot_is_testing <branch>: whether a branch is a TESTING sandbox. Uses is_testing_branch of
# git-flow-lib.sh when it is declared (5.0.0-RC1/git/testing_branch), else the same rule: the
# last segment is exactly branches.testing_leaf.
# Arguments: $1 branch. Returns: 0 when it is one, 1 otherwise.
ot_is_testing() {
	if declare -F is_testing_branch >/dev/null; then
		is_testing_branch "$1"
		return
	fi
	case "$1" in */"${QS_BR_TESTING:-TESTING}") return 0 ;; esac
	return 1
}

# ot_change_in <commit> <rev>: whether the change of a commit is already in <rev>: an empty
# change, the same stable patch-id as a commit of REL_CL_BASE..<rev>, or a diff that reverse-applies
# cleanly to the tree of <rev> (checked on a temporary index).
# Arguments: $1 commit, $2 revision. Returns: 0 when present, 1 otherwise.
ot_change_in() {
	local c="$1" rev="$2" pid idx rc=1
	pid="$(git diff "$c^" "$c" | git patch-id --stable | cut -d' ' -f1)"
	[ -n "$pid" ] || return 0
	if git log -p --no-merges --format='commit %H' "$rev" ${REL_CL_BASE:+"^$REL_CL_BASE"} -- |
		git patch-id --stable | cut -d' ' -f1 | grep -qxF "$pid"; then
		return 0
	fi
	idx="$(mktemp)"
	if git_idx "$idx" read-tree "$rev" 2>/dev/null &&
		git diff "$c^" "$c" | git_idx "$idx" apply --cached --check -R 2>/dev/null; then
		rc=0
	fi
	rm -f "$idx"
	return "$rc"
}

# ot_testing_clean <branch>: whether a TESTING sandbox inside the OT can be deleted with the tree
# (AC O7). Uses testing_release_ok (5.0.0-RC1/git/testing_branch) when it is declared. Fallback:
# the TESTING commits are the non-merge commits not reachable from the shas of its marker commit
# (the newest first-parent commit with 'Testing-Create: <ORIGINAL> <sha>'; 'Sources:' lines
# '<branch> <sha>'), the marker left out; each must already be in the OT ORIGINAL tip
# (ot_change_in). Warns on stderr naming the undistributed commits.
# Arguments: $1 TESTING branch; reads REL_TIP REL_CL_BASE. Returns: 0 when clean; 1 when it has
# undistributed commits or no readable marker (it is then set aside, never deleted).
ot_testing_clean() {
	local b="$1" ref m body s excl=() c pend=""
	if declare -F testing_release_ok >/dev/null; then
		testing_release_ok "$b"
		return
	fi
	ref="$(best_ref "$b" || true)"
	[ -n "$ref" ] || return 1
	m="$(git log --first-parent -n1 --format=%H --grep='^Testing-Create: ' "$ref" -- 2>/dev/null || true)"
	if [ -z "$m" ]; then
		echo "[rama] WARN: $b has no readable marker commit: set aside, not deleted" >&2
		return 1
	fi
	body="$(git log -n1 --format=%B "$m")"
	while IFS= read -r s; do
		[ -n "$s" ] && git cat-file -e "$s^{commit}" 2>/dev/null && excl+=("^$s")
	done < <(awk '/^Testing-Create: / { print $3 } /^Sources:$/ { on = 1; next } on && NF == 0 { on = 0 } on { print $2 }' <<<"$body")
	while IFS= read -r c; do
		[ -n "$c" ] && [ "$c" != "$m" ] || continue
		ot_change_in "$c" "$REL_TIP" || pend="$pend$c"$'\n'
	done < <(git rev-list --no-merges --reverse "$ref" ${excl[@]+"${excl[@]}"} --)
	[ -z "$pend" ] && return 0
	echo "[rama] WARN: $b has undistributed commits (git testing repartir):" >&2
	while IFS= read -r c; do
		[ -n "$c" ] && echo "         $(git log -n1 --format='%h %s' "$c")" >&2
	done <<<"$pend"
	return 1
}

# ot_branch_in <branch> <original>: whether a branch of the OT is already in its nearest ORIGINAL:
# branch_integrated (ancestry, or the 'Refs:'/'Squashed:' lines of a squash commit), or a simulated
# merge (git merge-tree --write-tree) of the branch into <original> that changes nothing, which
# proves nested squashes whose own ORIGINAL was squashed and deleted.
# Arguments: $1 branch, $2 ORIGINAL. Returns: 0 when in, 1 otherwise.
ot_branch_in() {
	local b="$1" p="$2" bt pt tree
	branch_integrated "$b" "$p" 2>/dev/null && return 0
	bt="$(branch_tip "$b")"
	pt="$(branch_tip "$p")"
	tree="$(git merge-tree --write-tree "$pt" "$bt" 2>/dev/null)" || return 1
	[ "$(head -n1 <<<"$tree")" = "$(git rev-parse "$pt^{tree}")" ]
}

# ot_release_analyse: analyse the OT REL_OT for its release; fills the REL_* variables of
# release_analyse plus REL_VTOP (the version ORIGINAL), REL_OT_TAG and REL_DONE, prints only the
# TESTING warnings. Errors (REL_ERRORS): no OT ORIGINAL (and no RELEASE), local and origin
# diverged, the version ORIGINAL not contained, no own non-merge commit, the tag on another
# commit, a RELEASE that does not contain the OT ORIGINAL tip (reopening a released OT is not
# supported), a branch of the OT checked out in another worktree. REL_DONE=1 when only the
# RELEASE is left (released); REL_RESUME=1 when RELEASE already contains the OT ORIGINAL tip.
# The delete lists leave out REL_TOP, which ot_release_run deletes last.
# Arguments: none. Returns: 0.
ot_release_analyse() {
	local v="${REL_OT%%/*}" b p tb tp n rt vt entry archived=$'\n' here wt
	REL_TOP="$REL_OT/$QS_BR_LEAF" REL_RELEASE="$REL_OT/$QS_BR_RELEASE_LEAF" REL_VTOP="$v/$QS_BR_LEAF"
	REL_ERRORS=() REL_OK=() REL_ARCHIVE=() REL_DELETE_LOCAL=() REL_DELETE_REMOTE=() REL_PLANNED=$'\n'
	REL_TIP="" REL_BASE="" REL_CL_BASE="" REL_RESUME=0 REL_DONE=0
	REL_OT_TAG="$(render_ot_tag "$REL_OT")"
	if [ -n "$REL_OT_TAG" ] && ! git check-ref-format "refs/tags/$REL_OT_TAG"; then
		REL_ERRORS+=("branches.ot_tag gives '$REL_OT_TAG', not a valid tag name")
	fi
	if ! exists_branch "$REL_TOP"; then
		if exists_branch "$REL_RELEASE"; then
			REL_DONE=1
		else REL_ERRORS+=("'$REL_TOP' does not exist (git arbol $v)"); fi
		return 0
	fi
	REL_TIP="$(branch_tip "$REL_TOP")"
	[ "$REL_TIP" = diverged ] && REL_ERRORS+=("$REL_TOP: local and origin diverged; run git subir on it first")
	if ! exists_branch "$REL_VTOP"; then
		REL_ERRORS+=("'$REL_VTOP' does not exist: the OT release starts from the version ORIGINAL")
	else
		vt="$(branch_tip "$REL_VTOP")"
		[ "$vt" = diverged ] && REL_ERRORS+=("$REL_VTOP: local and origin diverged; pull it first")
	fi
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		if ! git merge-base --is-ancestor "$vt" "$REL_TIP"; then
			REL_ERRORS+=("$REL_VTOP has $(git rev-list --count "$REL_TIP..$vt") commit(s) that $REL_TOP lacks; bring them in first: git checkout $REL_TOP && git subir")
		elif [ "$(git rev-list --count --no-merges "$REL_TIP" "^$vt")" = 0 ]; then
			REL_ERRORS+=("$REL_TOP has no commit of its own (integrate its branches first: git integra): nothing to release")
		else
			REL_CL_BASE="$vt" REL_BASE="$vt"
		fi
	fi
	if [ -n "$REL_OT_TAG" ] && exists_ref "refs/tags/$REL_OT_TAG" && [ "$REL_TIP" != diverged ] &&
		[ "$(git rev-parse "refs/tags/$REL_OT_TAG^{commit}")" != "$REL_TIP" ]; then
		REL_ERRORS+=("tag '$REL_OT_TAG' already exists on another commit (branches.ot_tag); move or delete it first")
	fi
	if exists_branch "$REL_RELEASE" && [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		rt="$(branch_tip "$REL_RELEASE")"
		if [ "$rt" != diverged ] && git merge-base --is-ancestor "$REL_TIP" "$rt"; then
			REL_RESUME=1 # an interrupted OT release: go on from there
		else
			REL_ERRORS+=("'$REL_RELEASE' exists and does not contain $REL_TOP: reopening an OT after its release is not supported")
		fi
	fi
	# every other branch of the OT against its nearest ORIGINAL; TESTING sandboxes never block (O7)
	while IFS= read -r b; do
		[ -n "$b" ] && [ "$b" != "$REL_TOP" ] && [ "$b" != "$REL_RELEASE" ] || continue
		tb="$(branch_tip "$b")"
		p="$(nearest_original "$b")"
		tp="$(branch_tip "$p")"
		if [ "$tb" = diverged ] || [ "$tp" = diverged ]; then
			REL_ERRORS+=("$([ "$tb" = diverged ] && echo "$b" || echo "$p"): local and origin diverged; run git subir on it first")
			continue
		fi
		if ot_is_testing "$b"; then
			if [ "$REL_TIP" != diverged ] && ot_testing_clean "$b"; then
				REL_OK+=("$b"$'\t'"$p (TESTING sandbox, nothing left to distribute)")
				continue
			fi
		elif ot_branch_in "$b" "$p"; then
			REL_OK+=("$b"$'\t'"$p")
			continue
		fi
		n="$(git rev-list --count --no-merges "$tp..$tb")"
		local new
		new="$(archive_name "$b")" || {
			REL_ERRORS+=("no free name to set '$b' aside")
			continue
		}
		REL_PLANNED="$REL_PLANNED$new"$'\n'
		REL_ARCHIVE+=("$b"$'\t'"$new"$'\t'"$p"$'\t'"$n")
	done < <(all_branches | awk -v p="$REL_OT/" 'index($0, p) == 1')
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do archived="$archived${entry%%$'\t'*}"$'\n'; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"} ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		b="${entry%%$'\t'*}"
		exists_ref "refs/remotes/origin/$b" && REL_DELETE_REMOTE+=("$b")
		case "$archived" in *$'\n'"$b"$'\n'*) continue ;; esac # set aside: renamed locally instead
		exists_ref "refs/heads/$b" && REL_DELETE_LOCAL+=("$b")
	done
	here="$(git rev-parse --show-toplevel)"
	while IFS= read -r wt; do
		b="${wt#*$'\t'}"
		b="${b#refs/heads/}"
		case "$b" in "$REL_OT"/*) REL_ERRORS+=("'$b' is checked out in another worktree; switch it or remove that worktree") ;; esac
	done < <(git worktree list --porcelain | awk -v h="$here" '/^worktree /{w=substr($0,10)} /^branch /{ if (w != h) print w "\t" $2 }')
	return 0
}

# ot_changelog_subject: the subject of the OT changelog commit, 'docs(changelog): <v> <ot>', or a
# shorter form when that is over the subject limit (commit.subject_max).
# Arguments: none; reads REL_OT. Returns: 0; prints the subject.
ot_changelog_subject() {
	local s max="${QS_COMMIT_SUBJECT_MAX:-50}"
	s="docs(changelog): ${REL_OT%%/*} ${REL_OT#*/}"
	[ "${#s}" -le "$max" ] || s="docs(changelog): ${REL_OT#*/}"
	[ "${#s}" -le "$max" ] || s="docs(changelog): OT release"
	printf '%s' "$s"
}

# ot_release_notes [--write]: the CHANGELOG.md section of the OT from the changelog engine: one
# line per first-parent change of the OT ORIGINAL since the version ORIGINAL, '(<hash>; <ot>)'.
# Arguments: extra options of qs.py release-notes (--write merges it into CHANGELOG.md of the
# current work tree). Returns: the exit status of the engine (1 when the suite image cannot run).
ot_release_notes() {
	local root
	root="$(git rev-parse --show-toplevel)"
	engine "$root" release-notes --version "$REL_VERSION" --tip "$REL_TIP" --base "$REL_CL_BASE" \
		--ot "${REL_OT#*/}" --tag "$REL_TAG" "$@"
}

# ot_changelog_commit: the first step of the OT release, kept apart because in 6.0.0 a DOCS branch
# takes it over: on the checked-out RELEASE, write the OT section into CHANGELOG.md and commit it
# (ot_changelog_subject). Skipped when there is no changelog file in the policy or when RELEASE
# already has commits of its own (a resumed release, AC O6).
# Arguments: none; reads REL_TIP REL_CL_BASE REL_OT REL_VERSION REL_TAG. Returns: 0; exits through
# die when the engine cannot write the file or a hook rejects the commit.
ot_changelog_commit() {
	[ -n "$QS_BR_CHANGELOG" ] || return 0
	if [ -n "$(git rev-list -n1 "$REL_TIP..HEAD")" ]; then
		say "$REL_RELEASE already has its changelog commit: resumed"
		return 0
	fi
	if ! { ot_release_notes --write >/dev/null 2>&1 && ot_changelog_try_commit; }; then
		# why: a dirty changelog would make the rerun die in require_clean
		git reset -q -- "$QS_BR_CHANGELOG" 2>/dev/null || true
		git checkout -q -- "$QS_BR_CHANGELOG" 2>/dev/null || true
		die "the changelog commit of $REL_RELEASE failed (see the hook message above); $QS_BR_CHANGELOG was restored. Fix the cause, then run git release again (it resumes)"
	fi
}

# ot_changelog_try_commit: commit QS_BR_CHANGELOG with the OT changelog subject, without dying.
# Arguments: none. Returns: 0 when committed or nothing to commit; 1 when the commit was rejected.
ot_changelog_try_commit() {
	git add -- "$QS_BR_CHANGELOG"
	git diff --cached --quiet && return 0
	git commit -q -m "$(ot_changelog_subject)" || return 1
	say "committed: $(ot_changelog_subject)"
}

# ot_tag_create: the annotated tag REL_OT_TAG on the OT ORIGINAL tip (nothing when branches.ot_tag
# is '' or the tag is already there, which the analysis checked).
# Arguments: none. Returns: 0.
ot_tag_create() {
	[ -n "$REL_OT_TAG" ] || return 0
	exists_ref "refs/tags/$REL_OT_TAG" && return 0
	git tag -a -m "OT ${REL_OT#*/} of ${REL_OT%%/*}: $REL_TOP at its release ($REL_RELEASE)" "$REL_OT_TAG" "$REL_TIP"
	say "tag $REL_OT_TAG created on $REL_TOP ($(git rev-parse --short "$REL_TIP"))"
}

# ot_release_report: the checks and the plan of the OT release (preview and before running).
# Arguments: none; reads the REL_* variables. Returns: 0.
ot_release_report() {
	local entry b p n new e i=1
	echo "## Checks"
	echo
	[ "${#REL_ERRORS[@]}" -eq 0 ] && echo "[ok] $REL_TOP is consistent (local/origin), contains $REL_VTOP and has its own commits"
	for e in ${REL_ERRORS[@]+"${REL_ERRORS[@]}"}; do echo "[!!] $e"; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"}; do
		IFS=$'\t' read -r b p <<<"$entry"
		echo "[ok] $b: contained in $p"
	done
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new p n <<<"$entry"
		echo "[!!] $b: $n commit(s) not in $p -> will be set aside as $new"
	done
	[ "$REL_RESUME" = 1 ] && echo "[ok] $REL_RELEASE exists and contains $REL_TOP: git release resumes from there"
	echo
	echo "## Plan"
	echo
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo "$i. set aside ${#REL_ARCHIVE[@]} branch(es) as $QS_BR_ARCHIVE/... (local and origin)"
		i=$((i + 1))
	fi
	echo "$i. $REL_TOP -> $REL_RELEASE with one commit \"$(ot_changelog_subject)\" ($QS_BR_CHANGELOG); $QS_BR_VERSION_FILE and the README badge untouched"
	i=$((i + 1))
	[ -n "$REL_OT_TAG" ] && echo "$i. annotated tag $REL_OT_TAG on $REL_TOP ($([ "$REL_TIP" = diverged ] && echo diverged || git rev-parse --short "$REL_TIP"))" && i=$((i + 1))
	echo "$i. push $REL_RELEASE${REL_OT_TAG:+ and $REL_OT_TAG}; delete the OT subtree: $((${#REL_DELETE_LOCAL[@]} + 1)) local branch(es)$(has_origin && [ "$REL_PUSH" = 1 ] && echo ", $((${#REL_DELETE_REMOTE[@]} + 1)) on origin at most") ($REL_TOP last)"
	i=$((i + 1))
	echo "$i. later: git release --version ${REL_OT%%/*} once every OT of ${REL_OT%%/*} has its RELEASE"
	return 0
}

# ot_release_changes: the first-parent changes of the OT ORIGINAL since the version ORIGINAL,
# oldest first, '- <short hash> <subject>'. Arguments: none. Returns: 0.
ot_release_changes() {
	echo "# OT release $REL_OT"
	echo
	echo "From \`$REL_TOP\` ($(git rev-parse --short "$REL_TIP")) since \`$REL_VTOP\` ($(git rev-parse --short "$REL_CL_BASE")):"
	echo
	git log --first-parent --no-merges --reverse --format='- %h %s' "$REL_TIP" "^$REL_CL_BASE" --
}

# ot_changelog_preview: git changelog inside an OT (AC O1): the OT changes, the CHANGELOG.md section
# the release would write, the checks and the plan. Changes nothing.
# Arguments: none; reads REL_OT REL_TAG_GIVEN. Returns: 0 when releasable (or already released);
# 1 when a check fails.
ot_changelog_preview() {
	[ "$REL_TAG_GIVEN" = 0 ] || die "the OT release takes no tag: its tag is branches.ot_tag ($(render_ot_tag "$REL_OT"))"
	fetch_origin
	ot_release_analyse
	if [ "$REL_DONE" = 1 ]; then
		say "$REL_OT is released on $REL_RELEASE: next, git release --version ${REL_OT%%/*} once every OT is released"
		return 0
	fi
	if [ -n "$REL_CL_BASE" ]; then
		ot_release_changes
		echo
		echo "## $QS_BR_CHANGELOG section (OT ${REL_OT#*/})"
		echo
		ot_release_notes 2>&1 || echo "(the suite image could not run: no changelog preview)"
		echo
	fi
	ot_release_report
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		echo
		say "not releasable yet: fix the [!!] items above"
		return 1
	fi
	echo
	say "preview only, nothing changed. Next: git release --ot $REL_OT"
}

# ot_release_run: carry out the analysed OT release: RELEASE created (or resumed) and checked out,
# the changelog commit, the tag, ONE push of RELEASE and the tag, the never-integrated branches set
# aside, the OT subtree deleted with the OT ORIGINAL last.
# Arguments: none; reads the REL_* variables. Returns: 0; exits through die when the push fails
# (nothing deleted yet: running git release again resumes).
ot_release_run() {
	local refs=()
	if ! exists_ref "refs/heads/$REL_RELEASE"; then
		git branch -q --no-track "$REL_RELEASE" "$([ "$REL_RESUME" = 1 ] && branch_tip "$REL_RELEASE" || echo "$REL_TIP")"
	elif [ "$REL_RESUME" = 1 ] && [ "$(branch_tip "$REL_RELEASE")" != "$(git rev-parse "refs/heads/$REL_RELEASE")" ]; then
		[ "$(current_branch || true)" = "$REL_RELEASE" ] && git checkout -q --detach
		git branch -q -f "$REL_RELEASE" "$(branch_tip "$REL_RELEASE")" # origin is ahead: catch up
	fi
	git checkout -q "$REL_RELEASE"
	ot_changelog_commit
	ot_tag_create
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		refs=("$REL_RELEASE")
		[ -n "$REL_OT_TAG" ] && refs+=("refs/tags/$REL_OT_TAG")
		git push -q --atomic -u origin "${refs[@]}" ||
			die "push of $REL_RELEASE failed; the OT tree is untouched. Fix it and run git release again (it resumes)"
	fi
	release_set_aside
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		[ "${#REL_DELETE_REMOTE[@]}" -eq 0 ] || git push -q origin --delete "${REL_DELETE_REMOTE[@]}"
		! exists_ref "refs/remotes/origin/$REL_TOP" || git push -q origin --delete "$REL_TOP"
	fi
	[ "${#REL_DELETE_LOCAL[@]}" -eq 0 ] || git branch -q -D "${REL_DELETE_LOCAL[@]}"
	! exists_ref "refs/heads/$REL_TOP" || git branch -q -D "$REL_TOP"
	say "OT $REL_OT released on $REL_RELEASE: $((${#REL_DELETE_LOCAL[@]} + 1)) branch(es) of the OT deleted, ${#REL_ARCHIVE[@]} set aside"
	return 0
}

# ot_release: git release for one OT (AC O1-O7): checks, preview, confirmation, then ot_release_run.
# Arguments: none; reads REL_OT REL_TAG_GIVEN REL_PUSH. Returns: 0; exits through die when a check
# fails or the human cancels (nothing changed).
ot_release() {
	[ "$REL_TAG_GIVEN" = 0 ] || die "the OT release takes no tag: its tag is branches.ot_tag ($(render_ot_tag "$REL_OT"))"
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	ot_release_analyse
	if [ "$REL_DONE" = 1 ]; then
		say "$REL_OT is already released on $REL_RELEASE. Next: git release --version ${REL_OT%%/*} once every OT is released"
		return 0
	fi
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		ot_release_report >&2
		die "nothing was changed"
	fi
	ot_release_changes
	echo
	ot_release_report
	echo
	confirm "Release OT $REL_OT on $REL_RELEASE?" || die "cancelled; nothing was changed"
	ot_release_run
	echo
	echo "Review now (you are on $REL_RELEASE):"
	echo "  git show HEAD                         # the $QS_BR_CHANGELOG section of OT ${REL_OT#*/}"
	echo "  \$EDITOR $QS_BR_CHANGELOG               # wording; then: git commit -am 'docs(changelog): review' && git push"
	return 0
}

# --- git combinar --------------------------------------------------------------------------------
# State of one run, set by cmd_combinar: CB_BASE the develop commit, CB_GD the state folder, CB_WT
# the temporary worktree. Helpers return through CB_* variables when a subshell would lose them.
# CB_ARCHIVE holds "<branch><TAB><archive name><TAB><tip>" per combined RELEASE; CB_ROLLBACK is 1
# while the local branches are being moved (CB_HEAD_REF / CB_HEAD_SHA: where HEAD was); CB_PWD and
# CB_PREV_TRAP are restored when the run ends.
CB_BASE="" CB_GD="" CB_WT="" CB_REL="" CB_ONLY="" CB_OUT="" CB_CONFLICTS=""
CB_N=0 CB_M=0 CB_K=0 CB_J=0
CB_ARCHIVE=() CB_ROLLBACK=0 CB_HEAD_REF="" CB_HEAD_SHA="" CB_PWD="" CB_PREV_TRAP=""

# combine_cleanup: undo what a git combinar run leaves behind. When it stops while the local
# branches are being moved, the branches and HEAD go back to where they were (all-or-nothing); if
# the undo is rejected (a branch moved meanwhile) HEAD stays detached, with a warning and the
# manual steps, never a symbolic ref to a missing branch;
# then the temporary worktree and the scratch files are removed and the directory is restored.
# Arguments: none. Exit status: 0 always (it runs from the EXIT trap).
combine_cleanup() {
	local undone
	# why: first, out of the temporary worktree that is removed below
	if [ -n "$CB_PWD" ]; then cd "$CB_PWD" 2>/dev/null || true; fi
	if [ "$CB_ROLLBACK" = 1 ]; then
		CB_ROLLBACK=0
		undone=1
		if [ -s "$CB_GD/combine.undo" ] && ! git update-ref --stdin <"$CB_GD/combine.undo"; then
			undone=0
			echo "[rama] ERROR: could not put the branches back; the old tips are in $CB_GD/combine.undo.keep" >&2
			cp "$CB_GD/combine.undo" "$CB_GD/combine.undo.keep" 2>/dev/null || true
		fi
		# why: HEAD goes back to its branch only when the undo worked and that branch exists, so it
		# never points at a branch that is gone; otherwise it stays detached where it is
		if [ "$undone" = 1 ]; then
			git checkout -q --detach "$CB_HEAD_SHA" 2>/dev/null || true
			if [ -n "$CB_HEAD_REF" ] && exists_ref "$CB_HEAD_REF"; then git symbolic-ref HEAD "$CB_HEAD_REF" 2>/dev/null || true; fi
			echo "[rama] the branches and HEAD were put back as they were" >&2
		else
			git checkout -q --detach 2>/dev/null || git update-ref --no-deref HEAD "$CB_HEAD_SHA" 2>/dev/null || true
			echo "[rama] WARN: HEAD was left detached (it was on ${CB_HEAD_REF:-$CB_HEAD_SHA}) because a branch moved meanwhile." >&2
			echo "  Check git branch -a, put the branches back from $CB_GD/combine.undo.keep" >&2
			echo "  (git update-ref --stdin < that file), then run: git switch ${CB_HEAD_REF#refs/heads/}" >&2
		fi
	fi
	if [ -n "$CB_WT" ] && [ -e "$CB_WT" ]; then
		git worktree remove --force "$CB_WT" >/dev/null 2>&1 || rm -rf "$CB_WT"
	fi
	git worktree prune 2>/dev/null || true
	if [ -n "$CB_GD" ]; then rm -f "$CB_GD"/combine.idx "$CB_GD"/combine.log "$CB_GD"/combine.msg \
		"$CB_GD"/combine.tx "$CB_GD"/combine.undo "$CB_GD"/combine.undo.new; fi
	return 0
}

# combine_trap_set: run combine_cleanup on EXIT and then the EXIT trap that was already set, so a
# caller's trap is kept (chained, not replaced).
# Arguments: none. Exit status: 0.
combine_trap_set() {
	# why: 'trap -p' quotes the command as shell words; eval of 'set --' gives it back as it was
	eval "set -- $(trap -p EXIT)"
	CB_PREV_TRAP="${3:-}"
	# shellcheck disable=SC2016 # why: expanded when the trap fires, not now
	trap 'combine_cleanup; eval "$CB_PREV_TRAP"' EXIT
}

# combine_finish: end of a run that got this far: clean up, and give back the previous EXIT trap.
# Arguments: none. Exit status: 0.
combine_finish() {
	combine_cleanup
	if [ -n "$CB_PREV_TRAP" ]; then trap -- "$CB_PREV_TRAP" EXIT; else trap - EXIT; fi
	return 0
}

# combine_mainline_merge <commit>: whether the commit is a merge whose second parent is in
# develop (the mainline brought into a tree: never replayed).
# Arguments: $1 a commit. Exit status: 0 when it is such a merge, 1 otherwise.
combine_mainline_merge() {
	local p2
	p2="$(git rev-parse -q --verify "$1^2" 2>/dev/null)" || return 1
	git merge-base --is-ancestor "$p2" "$CB_BASE"
}

# combine_paths <tip>: the release files of a tree (its commits not in develop). Sets CB_REL to
# the paths its release commits (RELEASE_COMMITS_RX) changed, and CB_ONLY to those of them that
# no other commit of the tree changed. Both are newline-framed lists ("\npath\n...\n").
# Arguments: $1 the tip. Exit status: 0; a git error ends the script.
combine_paths() {
	local line rel=0 own=$'\n' f
	CB_REL=$'\n' CB_ONLY=$'\n'
	while IFS= read -r line; do
		case "$line" in
		$'\x01'*) if [[ ${line#$'\x01'} =~ $RELEASE_COMMITS_RX ]]; then rel=1; else rel=0; fi ;;
		'') ;;
		*) if [ "$rel" = 1 ]; then CB_REL="$CB_REL$line"$'\n'; else own="$own$line"$'\n'; fi ;;
		esac
	done < <(git -c core.quotePath=false log --no-merges --no-renames --format='%x01%s' --name-only "$1" "^$CB_BASE" --)
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$own$CB_ONLY" in *$'\n'"$f"$'\n'*) ;; *) CB_ONLY="$CB_ONLY$f"$'\n' ;; esac
	done <<<"$CB_REL"
	return 0
}

# combine_normalize <commit> <paths>: the tree of the commit with each of the paths set to
# develop's version, or removed when develop lacks it (N() of the design: release files only
# release commits touched carry nothing worth replaying).
# Arguments: $1 a commit or tree; $2 a newline-framed list of paths.
# Output: the tree id. Exit status: 0; non-zero when git fails.
combine_normalize() {
	local f entry idx="$CB_GD/combine.idx"
	rm -f "$idx"
	git_idx "$idx" read-tree "$1"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		entry="$(git ls-tree --full-tree "$CB_BASE" -- "$f")"
		if [ -n "$entry" ]; then # "<mode> <type> <id><TAB><path>"
			git_idx "$idx" update-index --add --cacheinfo "$(awk '{ print $1 "," $3; exit }' <<<"$entry"),$f"
		else git_idx "$idx" update-index --force-remove -- "$f"; fi
	done <<<"$2"
	git_idx "$idx" write-tree
	rm -f "$idx"
}

# combine_take_mainline <tree> <ours> <merge base> <path>...: the merged tree with each conflicted
# path solved for develop: a three-way file merge that keeps develop's side of the conflicting
# hunks (git merge-file --theirs) and the other edits of <ours>; develop's file as it is when a
# side lacks it, and no file when develop has none.
# Arguments: $1 the merged tree (with conflict markers); $2 the tree side; $3 their merge base
#   (may be empty); $4... the conflicted release files.
# Output: the new tree id. Exit status: 0; non-zero when git fails.
combine_take_mainline() {
	local tree="$1" ours="$2" mb="$3" t="$CB_GD/combine" f mode blob
	shift 3
	rm -f "$t.idx"
	git_idx "$t.idx" read-tree "$tree"
	for f in "$@"; do
		mode="$(git ls-tree --full-tree "$CB_BASE" -- "$f" | awk '{ print $1; exit }')"
		if [ -z "$mode" ]; then
			git_idx "$t.idx" update-index --force-remove -- "$f"
			continue
		fi
		if [ -n "$mb" ] && git cat-file -e "$ours:$f" 2>/dev/null && git cat-file -e "$mb:$f" 2>/dev/null; then
			git cat-file blob "$ours:$f" >"$t.ours"
			git cat-file blob "$mb:$f" >"$t.base"
			git cat-file blob "$CB_BASE:$f" >"$t.theirs"
			# why: the exit status is the number of conflicts left; --theirs leaves none
			git merge-file -q -p --theirs "$t.ours" "$t.base" "$t.theirs" >"$t.out" || true
			blob="$(git hash-object -w "$t.out")"
		else blob="$(git rev-parse "$CB_BASE:$f")"; fi
		git_idx "$t.idx" update-index --add --cacheinfo "$mode,$blob,$f"
	done
	git_idx "$t.idx" write-tree
	rm -f "$t.idx" "$t.ours" "$t.base" "$t.theirs" "$t.out"
}

# combine_up_to_date <commit>: the commit with develop in it, without moving any branch. Sets
# CB_OUT to the commit itself when it contains develop, else to a temporary merge commit whose
# conflicts in release files (CB_REL of the commit) are solved for develop's side. Any other
# conflicted path goes to CB_CONFLICTS (one per line) and CB_OUT stays empty.
# Arguments: $1 a commit. Exit status: 0 on success; 1 when files other than release files
# conflict; a git error ends the script.
combine_up_to_date() {
	local c="$1" out tree f mb fixed=() rc=0
	CB_OUT="" CB_CONFLICTS=""
	if git merge-base --is-ancestor "$CB_BASE" "$c"; then
		CB_OUT="$c"
		return 0
	fi
	combine_paths "$c"
	out="$(git -c core.quotePath=false merge-tree --write-tree --name-only --no-messages "$c" "$CB_BASE")" || rc=$?
	[ "$rc" -le 1 ] || die "git merge-tree failed on $(git rev-parse --short "$c") (Git 2.38 or newer is needed): $out"
	tree="$(sed -n 1p <<<"$out")"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$CB_REL" in *$'\n'"$f"$'\n'*) fixed+=("$f") ;; *) CB_CONFLICTS="$CB_CONFLICTS$f"$'\n' ;; esac
	done < <(sed 1d <<<"$out" | LC_ALL=C sort -u)
	[ -z "$CB_CONFLICTS" ] || return 1
	if [ "${#fixed[@]}" -gt 0 ]; then
		mb="$(git merge-base "$c" "$CB_BASE" | sed -n 1p)"
		tree="$(combine_take_mainline "$tree" "$c" "$mb" "${fixed[@]}")"
	fi
	CB_OUT="$(git commit-tree "$tree" -p "$c" -p "$CB_BASE" -m "Merge branch '$QS_BR_MAINLINE' (git combinar, temporary)")"
}

# combine_originals <tip>: the original RELEASE tips a combined RELEASE squashed, read from the
# 'Squashes: <branch> <sha>' lines of its chore(combine) commits that are not in develop.
# Arguments: $1 the tip. Output: "<branch> <sha>" lines, oldest first, each sha once; shas that no
# longer exist are left out with a warning. Exit status: 0.
combine_originals() {
	local b s seen=$'\n'
	while read -r b s; do
		case "$seen" in *$'\n'"$s"$'\n'*) continue ;; esac
		seen="$seen$s"$'\n'
		if git cat-file -e "$s^{commit}" 2>/dev/null; then
			printf '%s %s\n' "$b" "$s"
		else echo "[rama] WARN: $b $s, named by a squash of $(git rev-parse --short "$1"), is gone: left out" >&2; fi
	done < <(git log --reverse --grep='^chore(combine)' --format=%B "$1" "^$CB_BASE" -- |
		sed -n 's/^Squashes: \([^ ]*\) \([0-9a-f]\{40\}\)[[:space:]]*$/\1 \2/p')
	return 0
}

# combine_tree_date <tip> <version>: when a tree was created, from author dates (a rebase or a
# cherry-pick keeps them; the committer date changes). A combined RELEASE (it has chore(combine)
# commits not in develop) takes the earliest author date of its squash commits: git combinar
# writes each squash with the date of what it squashes. Any other tree takes the author date of
# its version commit (the oldest one not in develop whose subject is the version subject of
# <version>, made by git np or git nueva-version), or of its oldest commit not in develop.
# Arguments: $1 the tip; $2 its version. Output: seconds since the epoch, or nothing when the tree
# has no commit of its own. Exit status: 0.
combine_tree_date() {
	local tip="$1" vs d
	vs="$(version_subject "$2")"
	d="$(git log --format=%at --grep='^chore(combine)' "$tip" "^$CB_BASE" -- | sort -n | sed -n 1p)"
	if [ -z "$d" ]; then
		# why: awk reads everything (no exit); an early exit would end git with SIGPIPE under pipefail
		d="$(git log --reverse --format='%at%x1f%s' "$tip" "^$CB_BASE" -- | awk -F'\037' -v s="$vs" '$2 == s && !n++ { print $1 }')"
	fi
	[ -n "$d" ] || d="$(git log --reverse --format=%at "$tip" "^$CB_BASE" -- | sed -n 1p)"
	printf '%s' "$d"
}

# combine_order_key <version> <tip> [<branch> <sha>]...: the creation order key of a tree: the
# earliest combine_tree_date of its tip and of the originals it squashed (the 'Squashes:' lines;
# the ones that are gone are not given, and the squash dates stand in for them), then how many
# commits not in develop they have together. A copy (git nueva-version) has a later version
# commit than its source, and more commits when both fall in the same second, so it sorts after.
# Arguments: $1 the version of the tree; $2 its tip; then pairs of original branch and sha.
# Output: "<seconds since the epoch><TAB><count>". Exit status: 0.
combine_order_key() {
	local d t tips=("$2")
	t="$(combine_tree_date "$2" "$1")"
	shift 2
	while [ "$#" -ge 2 ]; do
		tips+=("$2")
		d="$(combine_tree_date "$2" "$(branch_version "$1")")"
		if [ -n "$d" ] && { [ -z "$t" ] || [ "$d" -lt "$t" ]; }; then t="$d"; fi
		shift 2
	done
	printf '%s\t%s\n' "${t:-0}" "$(git rev-list --count "${tips[@]}" "^$CB_BASE" --)"
}

# combine_copy_point <tip> <earlier>...: where a tree was copied from one combined before it (git
# nueva-version): the newest commit of its first-parent line, not in develop, that an earlier tip
# contains.
# Arguments: $1 the tip; $2... the tips (and originals) already combined.
# Output: "<copy point> <earlier tip that contains it>", or nothing. Exit status: 0.
combine_copy_point() {
	local tip="$1" c d
	shift
	[ "$#" -gt 0 ] || return 0
	while IFS= read -r c; do
		for d in "$@"; do
			if git merge-base --is-ancestor "$c" "$d"; then
				printf '%s %s\n' "$c" "$d"
				return 0
			fi
		done
	done < <(git rev-list --first-parent "$tip" "^$CB_BASE" --)
	return 0
}

# combine_only_release_after <source> <copy point>: whether all the source tree got after the copy
# point (and develop lacks) is release commits and mainline merges.
# Arguments: $1 the source tip; $2 the copy point. Exit status: 0 when so, 1 otherwise.
combine_only_release_after() {
	local h s
	while IFS=$'\x1f' read -r h s; do
		[[ $s =~ $RELEASE_COMMITS_RX ]] && continue
		combine_mainline_merge "$h" || return 1
	done < <(git log --format='%H%x1f%s' "$1" "^$2" "^$CB_BASE" --)
	return 0
}

# combine_counts <tip> <exclude>...: what the squash of one RELEASE takes and drops. Sets CB_N (own
# commits squashed), CB_M (mainline merges), CB_K (release commits) and CB_J (commits an earlier
# tree already brought).
# Arguments: $1 the tip; $2... the tips already combined. Exit status: 0.
combine_counts() {
	local tip="$1" h s e all ex=()
	shift
	for e in "$@"; do ex+=("^$e"); done
	CB_N=0 CB_M=0 CB_K=0
	all="$(git rev-list --count "$tip" "^$CB_BASE" --)"
	while IFS=$'\x1f' read -r h s; do
		if combine_mainline_merge "$h"; then
			CB_M=$((CB_M + 1))
		elif [[ $s =~ $RELEASE_COMMITS_RX ]]; then
			CB_K=$((CB_K + 1))
		else CB_N=$((CB_N + 1)); fi
	done < <(git log --format='%H%x1f%s' "$tip" "^$CB_BASE" ${ex[@]+"${ex[@]}"} --)
	CB_J=$((all - CB_N - CB_M - CB_K))
}

# combine_subject <version>: the subject of the squash of one version, within the subject limit.
# Arguments: $1 the version. Output: the subject. Exit status: 0.
combine_subject() {
	local s="chore(combine): $1 changes"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore(combine): $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: combine $1"
	printf '%s' "$s"
}

# combine_message <version> <tip> <squashes> <exclude>...: the message of the squash of one
# RELEASE. The body lists, oldest first, the subjects of its own first-parent commits that are not
# release commits or mainline merges (with the OT of their 'Refs:' line); an earlier squash
# (a combined RELEASE) contributes its own list. Then the 'Squashes:' lines.
# Arguments: $1 the version; $2 its tip; $3 the 'Squashes: ...' lines; $4... the tips already
# combined. Output: the message. Exit status: 0.
combine_message() {
	local v="$1" tip="$2" sq="$3" h s e src ot lines="" ex=()
	shift 3
	for e in "$@"; do ex+=("^$e"); done
	while IFS=$'\x1f' read -r h s; do
		[[ $s =~ $RELEASE_COMMITS_RX ]] && continue
		combine_mainline_merge "$h" && continue
		if [[ $s =~ ^chore\(combine\) ]]; then
			lines="$lines$(git log -1 --format=%B "$h" | grep '^- ' || true)"$'\n'
			continue
		fi
		src="$(git log -1 --format=%B "$h" | sed -n 's/^Refs: \([^ ]*\) -> .*/\1/p' | sed -n 1p)"
		ot=""
		case "$src" in */*/*) ot="$(branch_ot "$src")" ;; esac
		lines="$lines- $s${ot:+ (OT $ot)}"$'\n'
	done < <(git log --first-parent --reverse --format='%H%x1f%s' "$tip" "^$CB_BASE" ${ex[@]+"${ex[@]}"} --)
	combine_subject "$v"
	printf '\n\n'
	lines="$(grep -v '^$' <<<"$lines" || true)"
	[ -z "$lines" ] || printf '%s\n\n' "$lines"
	printf '%s\n' "$sq"
}

# combine_archive_plan <branch> <tip>...: the archive name of each combined RELEASE
# ('unmerged/<branch>': kept, not deleted, so the changelog refs and the 'Squashes:' shas still
# resolve), added to CB_ARCHIVE, and the plan printed: what is renamed locally and on origin
# (there the old name is deleted). Nothing is changed yet.
# Arguments: pairs of RELEASE branch and tip. Output: the plan lines.
# Exit status: 0; ends the script through die when no free name is left.
combine_archive_plan() {
	local b new
	REL_PLANNED=$'\n' CB_ARCHIVE=()
	while [ "$#" -ge 2 ]; do
		b="$1"
		new="$(archive_name "$b")" || die "no free name to set '$b' aside; nothing was changed"
		REL_PLANNED="$REL_PLANNED$new"$'\n'
		CB_ARCHIVE+=("$b"$'\t'"$new"$'\t'"$2")
		if exists_ref "refs/heads/$b"; then echo "  local:  $b -> $new"; else echo "  local:  $new (copy of origin/$b)"; fi
		if has_origin && exists_ref "refs/remotes/origin/$b"; then
			echo "  origin: $b -> $new  (renamed on origin: $b is deleted there)"
		fi
		shift 2
	done
	echo "  local:  $REL_RELEASE $(if exists_ref "refs/heads/$REL_RELEASE"; then echo "moves to the combined result"; else echo "created"; fi)"
	if has_origin; then echo "  origin: $REL_RELEASE pushed; all origin changes in one atomic push, at the end"; fi
}

# combine_apply <result>: move the local branches in one transaction (git update-ref --stdin):
# REL_RELEASE to the result, each CB_ARCHIVE entry renamed, then check out REL_RELEASE. HEAD is
# detached first; the undo file (combine.undo) is written before any branch moves, and while
# CB_ROLLBACK is 1 a failure puts every branch and HEAD back (combine_cleanup, from the EXIT
# trap; if a branch moved meanwhile and the undo is rejected, HEAD stays detached with a warning).
# Arguments: $1 the combined result. Exit status: 0; ends the script through die on a failure,
# with nothing changed.
combine_apply() {
	local res="$1" tx="$CB_GD/combine.tx" undo="$CB_GD/combine.undo" old entry b new t
	: >"$tx"
	: >"$undo.new"
	for entry in ${CB_ARCHIVE[@]+"${CB_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new t <<<"$entry"
		printf 'create refs/heads/%s %s\n' "$new" "$t" >>"$tx"
		printf 'delete refs/heads/%s %s\n' "$new" "$t" >>"$undo.new"
		if [ "$b" != "$REL_RELEASE" ] && exists_ref "refs/heads/$b"; then
			old="$(git rev-parse "refs/heads/$b")"
			printf 'delete refs/heads/%s %s\n' "$b" "$old" >>"$tx"
			printf 'create refs/heads/%s %s\n' "$b" "$old" >>"$undo.new"
		fi
	done
	if exists_ref "refs/heads/$REL_RELEASE"; then
		old="$(git rev-parse "refs/heads/$REL_RELEASE")"
		printf 'update refs/heads/%s %s %s\n' "$REL_RELEASE" "$res" "$old" >>"$tx"
		printf 'update refs/heads/%s %s %s\n' "$REL_RELEASE" "$old" "$res" >>"$undo.new"
	else
		printf 'create refs/heads/%s %s\n' "$REL_RELEASE" "$res" >>"$tx"
		printf 'delete refs/heads/%s %s\n' "$REL_RELEASE" "$res" >>"$undo.new"
	fi
	CB_HEAD_REF="$(git symbolic-ref -q HEAD || true)"
	CB_HEAD_SHA="$(git rev-parse HEAD)"
	# why: the undo file is complete on disk before any branch moves, so a kill at any point leaves it
	mv "$undo.new" "$undo"
	CB_ROLLBACK=1
	# why: a branch checked out here may be renamed; a detached HEAD at the same commit leaves the
	# work tree as it is
	git checkout -q --detach || die "could not detach HEAD; nothing was changed"
	# why: the transaction is all or nothing, so when it fails there is nothing to undo
	git update-ref --stdin <"$tx" || {
		rm -f "$undo"
		die "could not move the local branches; nothing was changed"
	}
	git checkout -q "$REL_RELEASE" || die "could not check out $REL_RELEASE; nothing was changed"
	CB_ROLLBACK=0
	rm -f "$undo" "$tx"
}

# combine_push: publish the local result on origin in one atomic push (git push --atomic): the new
# REL_RELEASE, and each combined RELEASE that origin has renamed to its archive name. Every ref
# origin had is protected by --force-with-lease with the value last fetched. A failure keeps the
# local result and prints the push to run by hand.
# Arguments: none. Output: progress. Exit status: 0 when pushed or there is no origin; ends the
# script through die when the push fails.
combine_push() {
	local entry b new t n=0 args=() lease=()
	has_origin || return 0
	args=("refs/heads/$REL_RELEASE:refs/heads/$REL_RELEASE")
	if exists_ref "refs/remotes/origin/$REL_RELEASE"; then
		lease+=("--force-with-lease=refs/heads/$REL_RELEASE:$(git rev-parse "refs/remotes/origin/$REL_RELEASE")")
	fi
	for entry in ${CB_ARCHIVE[@]+"${CB_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new t <<<"$entry"
		exists_ref "refs/remotes/origin/$b" || continue
		args+=("$t:refs/heads/$new")
		n=$((n + 1))
		if [ "$b" != "$REL_RELEASE" ]; then
			args+=(":refs/heads/$b")
			lease+=("--force-with-lease=refs/heads/$b:$(git rev-parse "refs/remotes/origin/$b")")
		fi
	done
	if ! git push -q --atomic -u origin ${lease[@]+"${lease[@]}"} "${args[@]}"; then
		cat >&2 <<EOF
[rama] the push to origin failed: origin is unchanged; the local result is kept ($REL_RELEASE, and
  the combined RELEASE branches renamed locally). When origin accepts pushes again, run:
  git push --atomic -u origin ${lease[*]} ${args[*]}
  Then review $QS_BR_CHANGELOG on $REL_RELEASE and run git publicar --version $(branch_version "$REL_RELEASE").
EOF
		die "push to origin failed"
	fi
	say "origin: $REL_RELEASE pushed; $n RELEASE branch(es) renamed there"
}

# combine_stale_help: how to bring develop into a RELEASE by hand when combinar cannot do it.
# Arguments: none. Output: the suggested resolution, on stderr. Exit status: 0.
combine_stale_help() {
	cat >&2 <<EOF
  Then resolve: $QS_BR_CHANGELOG keeps the entries of both sides in semver order; $QS_BR_VERSION_FILE and
  the pom version keep the RELEASE version (the qs-version merge driver does it); the README badge
  and CITATION.cff keep the RELEASE version; other files are real conflicts: fix them by hand.
  Commit the merge and run git combinar again.
EOF
}

# git combinar: join several '<v>/RELEASE' branches into '<target>/RELEASE'. The result starts at
# develop and gets, oldest tree first, one squash commit per RELEASE with only its own changes
# (no develop content, no release commits, nothing an earlier tree brought), then the version,
# changelog and readme commits of the target. The CHANGELOG.md entry is built from the original
# histories. The joined RELEASE branches are kept as 'unmerged/<v>/RELEASE', locally and on origin.
# All or nothing: every commit (squashes and release commits) is made in a temporary worktree
# first; then the local branches move in one transaction (put back on any failure), and last
# origin gets one atomic push.
# Arguments: --version <v>, --incluir <v1,v2...>, and --yes (global). Output: plan and progress.
# Exit status: 0 on success; 1 (through die) on a bad argument, a conflict or a failed step, with
# nothing changed; when only the push to origin fails, the local result is kept and the push to
# run by hand is printed.
cmd_combinar() {
	local target="" incl="" rels=() chosen=() ordered=() done_tips=() links=() r t c d cp src bad=0
	local btree ntree p s h tree sq made here wt b m only res pairs=()
	local -A tip=() up=() orig=() okey=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--version)
			target="${2:?--version needs a version}"
			shift
			;;
		--version=*) target="${1#--version=}" ;;
		--incluir | --include)
			incl="${2:?$1 needs versions}"
			shift
			;;
		--incluir=* | --include=*) incl="${1#*=}" ;;
		*) die "unknown argument '$1' (combinar: --version <v>, --incluir <v1,v2...>, --yes)" ;;
		esac
		shift
	done
	require_clean || die "working tree not clean: commit or stash first"
	CB_PWD="$PWD"
	combine_trap_set
	# why: the index and tree paths below are relative to the top of the work tree (combine_cleanup
	# goes back to CB_PWD)
	cd "$(git rev-parse --show-toplevel)"
	fetch_origin
	CB_BASE="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$CB_BASE" ] || die "'$QS_BR_MAINLINE' does not exist"
	CB_BASE="$(git rev-parse "$CB_BASE^{commit}")"
	mapfile -t rels < <(release_branches)
	[ "${#rels[@]}" -ge 2 ] || die "combinar needs two or more RELEASE branches (now: ${rels[*]:-none}); prepare them with git release --version <v>"
	for r in "${rels[@]}"; do
		t="$(branch_tip "$r")"
		[ "$t" = diverged ] && die "$r: local and origin diverged; pull it first"
		tip[$r]="$t"
	done
	# which ones: --incluir, or a yes/no question for each
	for r in "${rels[@]}"; do
		if [ -n "$incl" ]; then
			case ",$incl," in *",$(branch_version "$r"),"* | *",$r,"*) chosen+=("$r") ;; esac
		elif confirm "Combine $r ($(git rev-list --count --no-merges "${tip[$r]}" "^$CB_BASE") commit(s))?"; then
			chosen+=("$r")
		fi
	done
	[ "${#chosen[@]}" -ge 2 ] || die "choose two or more RELEASE branches to combine (chosen: ${chosen[*]:-none})"
	if [ -z "$target" ]; then
		[ "$YES" = 1 ] && die "--yes needs --version <version of the combined release>"
		printf 'Version of the combined release (e.g. %s): ' "$(next_version patch)" >/dev/tty
		read -r target </dev/tty || target=""
	fi
	printf '%s' "$target" | grep -qE -- "$(_br_level_re 1)" || die "'$target' is not a version of the branch model (semver: 6.22.7)"
	REL_RELEASE="$target/$QS_BR_RELEASE_LEAF"
	if exists_branch "$REL_RELEASE"; then
		case " ${chosen[*]} " in *" $REL_RELEASE "*) ;; *) die "'$REL_RELEASE' exists and is not among the chosen ones" ;; esac
	fi
	taken "$target/$QS_BR_LEAF" && die "'$target/$QS_BR_LEAF' exists: that tree is not released yet"
	# the joined branches are renamed at the end: none may be checked out in another worktree
	here="$(git rev-parse --show-toplevel)"
	while IFS=$'\t' read -r wt b; do
		case " ${chosen[*]} " in *" ${b#refs/heads/} "*) die "'${b#refs/heads/}' is checked out in another worktree ($wt): switch it or remove that worktree; nothing was changed" ;; esac
	done < <(git worktree list --porcelain | awk -v h="$here" '/^worktree /{w=substr($0,10)} /^branch /{ if (w != h) print w "\t" $2 }')
	CB_GD="$(git rev-parse --absolute-git-dir)/quality-suite"
	mkdir -p "$CB_GD"

	# 1. every RELEASE up to date with develop: a temporary merge commit when it is not
	for r in "${chosen[@]}"; do
		t="${tip[$r]}"
		orig[$r]="$(combine_originals "$t")"
		git merge-base --is-ancestor "$CB_BASE" "$t" ||
			echo "[rama] WARN: $r lacks $(git rev-list --count "$t..$CB_BASE") commit(s) of $QS_BR_MAINLINE: merging $QS_BR_MAINLINE into a temporary commit (no branch moves)" >&2
		if combine_up_to_date "$t"; then
			up[$r]="$CB_OUT"
		else
			bad=1
			echo "[rama] $r: merging $QS_BR_MAINLINE conflicts in files that are not release files:" >&2
			sed '/^$/d; s/^/    /' <<<"$CB_CONFLICTS" >&2
			echo "  Bring $QS_BR_MAINLINE in by hand: git checkout $r && git merge $QS_BR_MAINLINE" >&2
		fi
	done
	if [ "$bad" = 1 ]; then
		combine_stale_help
		die "nothing was changed"
	fi
	# 2. creation order (combine_order_key): author dates, so a rebase or a cherry-pick does not
	# change it; a combined RELEASE takes the earliest date of what it squashed
	for r in "${chosen[@]}"; do
		# shellcheck disable=SC2046 # why: "<branch> <sha>" lines, one word each
		okey[$r]="$(combine_order_key "$(branch_version "$r")" "${tip[$r]}" $(printf '%s' "${orig[$r]}"))"
	done
	mapfile -t ordered < <(for r in "${chosen[@]}"; do printf '%s\t%s\n' "${okey[$r]}" "$r"; done |
		sort -t $'\t' -k1,1n -k2,2n -k3,3 | cut -f3-)
	[ "${#ordered[@]}" -eq "${#chosen[@]}" ] || die "could not order the RELEASE branches by creation"
	echo "Combine into $REL_RELEASE, on $QS_BR_MAINLINE ($(git rev-parse --short "$CB_BASE")), oldest first; one squash commit"
	echo "per RELEASE with its own changes; their version/changelog/readme commits are written again for $target:"
	for r in "${ordered[@]}"; do
		echo "  $r$([ -n "${orig[$r]}" ] && echo "  (combined from: $(cut -d' ' -f1 <<<"${orig[$r]}" | tr '\n' ' '))")"
		pairs+=("$r" "${tip[$r]}")
	done
	echo "Then, when every commit is made (all or nothing):"
	combine_archive_plan "${pairs[@]}"
	confirm "Go on (local and origin changes above)?" || die "cancelled; nothing was changed"

	# 3.-6. one squash per RELEASE, in a temporary worktree detached at develop
	CB_WT="$CB_GD/combine-wt"
	rm -rf "$CB_WT"
	git worktree prune
	git worktree add -q --detach "$CB_WT" "$CB_BASE" >/dev/null 2>&1 || die "could not create a temporary worktree; nothing was changed"
	# why: the hooks of the release commits read the git-ignored rules of this work tree
	if [ -f "$here/.quality-rules.json" ]; then cp "$here/.quality-rules.json" "$CB_WT/"; fi
	for r in "${ordered[@]}"; do
		t="${tip[$r]}"
		combine_paths "$t"
		only="$CB_ONLY"
		btree="$(git rev-parse "$CB_BASE^{tree}")"
		cp="$(combine_copy_point "$t" ${done_tips[@]+"${done_tips[@]}"})"
		if [ -n "$cp" ]; then
			read -r c d <<<"$cp"
			# why: the source's own develop merge holds the resolution when it only added release commits
			if combine_only_release_after "$d" "$c"; then src="$d"; else src="$c"; fi
			if ! combine_up_to_date "$src"; then
				echo "[rama] $r is a copy of an earlier tree ($(git rev-parse --short "$c")) that conflicts with $QS_BR_MAINLINE in:" >&2
				sed '/^$/d; s/^/    /' <<<"$CB_CONFLICTS" >&2
				die "nothing was changed. Merge $QS_BR_MAINLINE into the RELEASE it was copied from, or combine fewer"
			fi
			btree="$(combine_normalize "$CB_OUT" "$only")"
			say "$r: copied from an earlier tree at $(git rev-parse --short "$c"); only what it added since is squashed"
		fi
		ntree="$(combine_normalize "${up[$r]}" "$only")"
		combine_counts "$t" ${done_tips[@]+"${done_tips[@]}"}
		if [ -n "${orig[$r]}" ]; then
			sq="Squashes: ${orig[$r]//$'\n'/$'\n'Squashes: }"$'\n'"Squashes: $r $t"
		else sq="Squashes: $r $t"; fi
		made=0
		if [ "$ntree" != "$btree" ]; then
			p="$(git commit-tree "$btree" -m "git combinar: base of $r (temporary)")"
			s="$(git commit-tree "$ntree" -p "$p" -m "git combinar: $r (temporary)")"
			if ! git -C "$CB_WT" cherry-pick --no-commit "$s" >"$CB_GD/combine.log" 2>&1; then
				tree="$(git -C "$CB_WT" diff --name-only --diff-filter=U)"
				if [ -n "$tree" ] || ! git -C "$CB_WT" diff --cached --quiet; then
					echo "[rama] $r conflicts with the RELEASE branches before it in:" >&2
					sed '/^$/d; s/^/    /' <<<"${tree:-$(cat "$CB_GD/combine.log")}" >&2
					die "nothing was changed. Merge them by hand on one RELEASE branch, or combine fewer"
				fi
			fi
			tree="$(git -C "$CB_WT" write-tree)"
			h="$(git -C "$CB_WT" rev-parse HEAD)"
			if [ "$tree" != "$(git rev-parse "$h^{tree}")" ]; then
				combine_message "$(branch_version "$r")" "$t" "$sq" ${done_tips[@]+"${done_tips[@]}"} >"$CB_GD/combine.msg"
				# why: the squash keeps the creation date of what it squashes (the order of a later combinar)
				h="$(GIT_AUTHOR_DATE="${okey[$r]%%$'\t'*} +0000" git commit-tree "$tree" -p "$h" -F "$CB_GD/combine.msg")"
				made=1
			fi
			git -C "$CB_WT" reset -q --hard "$h"
		fi
		say "$r: $CB_N own commit(s) squashed; dropped $CB_M mainline merge(s), $CB_K release commit(s), $CB_J already combined$([ "$made" = 1 ] || echo "; nothing new, no squash commit")"
		done_tips+=("$t")
		if [ -n "${orig[$r]}" ]; then
			while read -r b c; do
				done_tips+=("$c")
				links+=("$c")
			done <<<"${orig[$r]}"
		fi
		links+=("$t")
	done
	# 7. the changelog reads the original histories: a chain of temporary merges on develop
	m="$CB_BASE"
	for c in "${links[@]}"; do
		m="$(git commit-tree "$c^{tree}" -p "$m" -p "$c" -m "Combine $(git rev-parse --short "$c") (git combinar, temporary)")"
	done
	# 8. the release commits of the new version, still in the temporary worktree (no branch moved)
	REL_VERSION="$target" REL_TIP="$m" REL_CL_BASE="$CB_BASE" REL_PUSH=1
	REL_TAG="$(render_tag "$target/$QS_BR_LEAF")"
	REL_AGAIN="nothing was changed; fix it and run git combinar again"
	# why: no subshell, so errexit still applies inside; every die there says nothing was changed,
	# and combine_cleanup goes back to CB_PWD
	cd "$CB_WT"
	release_commits
	cd "$here"
	res="$(git -C "$CB_WT" rev-parse HEAD)"
	git worktree remove --force "$CB_WT"
	CB_WT=""
	# 9. the local branches in one transaction: REL_RELEASE on the result, the joined RELEASE
	# branches renamed (kept, so their history stays reachable); HEAD on REL_RELEASE
	combine_apply "$res"
	git config "qs.release.$target.tag" "$REL_TAG"
	for r in "${chosen[@]}"; do
		[ "$r" = "$REL_RELEASE" ] || git config --unset "qs.release.$(branch_version "$r").tag" 2>/dev/null || true
	done
	for c in "${CB_ARCHIVE[@]}"; do say "${c%%$'\t'*} kept as $(cut -f2 <<<"$c")"; done
	# 10. origin last, in one atomic push
	combine_push
	combine_finish
	say "combined ${#chosen[@]} release(s) into $REL_RELEASE; RELEASE branches now: $(release_branches | tr '\n' ' ')"
	echo "Review $QS_BR_CHANGELOG on $REL_RELEASE, then: git publicar --version $target"
}

cmd_repo_files() { # create the missing standard repository files (README, CHANGELOG, VERSION...)
	local root
	root="$(git rev-parse --show-toplevel)"
	# why: the option loop above already took --force
	if [ "$FORCE" = 1 ]; then set -- --force "$@"; fi
	engine "$root" repo-files "$@" || die "the suite image could not run (Docker?)"
}

case "$CMD" in
nueva-padre | np) cmd_nueva padre "$@" ;;
nueva-final | nr) cmd_nueva final "$@" ;;
convertir-padre) cmd_convertir ;;
subir) cmd_subir ;;
integra) cmd_integra ;;
arbol) cmd_arbol "$@" ;;
estructura | es) cmd_estructura "$@" ;;
changelog) cmd_changelog "$@" ;;
release) cmd_release "$@" ;;
publicar | publish) cmd_publicar "$@" ;;
nueva-version | nv) cmd_nueva_version "$@" ;;
combinar | combine) cmd_combinar "$@" ;;
repo-files | ficheros-repo) cmd_repo_files "$@" ;;
*)
	awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
	exit 2
	;;
esac
