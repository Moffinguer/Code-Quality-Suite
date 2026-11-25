#!/usr/bin/env bash
# rama/release-common.sh - what the release pipelines share (module of git-rama.sh).
# Sourced by rama/release.sh; defines functions only. The version, OT and combine releases call
# these helpers instead of repeating the same blocks.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2154

# rel_changelog_preview <heading> <notes function> <report function> <next>: the common part of
# git changelog for an OT and for a version: the CHANGELOG.md section the release would write (when
# <heading> is not empty), the checks and the plan, and the verdict.
# Arguments: $1 heading of the section ('' for no section); $2 function that prints the notes;
# $3 function that prints the checks and the plan; $4 the command to suggest next. Reads REL_ERRORS.
# Returns: 0 when releasable; 1 when a check fails.
rel_changelog_preview() {
	if [ -n "$1" ]; then
		echo "$1"
		echo
		"$2" 2>&1 || echo "(the suite image could not run: no changelog preview)"
		echo
	fi
	"$3"
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		echo
		say "not releasable yet: fix the [!!] items above"
		return 1
	fi
	echo
	say "preview only, nothing changed. Next: $4"
}

# rel_union_notes <inputs function> [release-notes option]...: the CHANGELOG.md entry that unites
# several sections. Makes the scratch folder '.qs-release-union' in the work tree (the engine sees
# only the work tree), lets <inputs function> write the inputs, runs qs.py release-notes --union and
# removes the folder.
# Arguments: $1 function called as '<fn> <root> <dir>' that appends the inputs (paths relative to
# the root) to the caller's array 'files' and sets 'rc' to 1 when the engine failed; the rest goes to
# release-notes. Reads REL_VERSION and REL_TAG. Returns: the exit status of the engine.
rel_union_notes() {
	local fn="$1" root dir files=() rc=0
	shift
	root="$(git rev-parse --show-toplevel)"
	dir=".qs-release-union"
	rm -rf -- "${root:?}/$dir"
	mkdir -p "$root/$dir"
	"$fn" "$root" "$dir"
	if [ "$rc" = 0 ]; then
		if [ "${#files[@]}" -eq 0 ]; then
			: >"$root/$dir/empty.md"
			files=("$dir/empty.md")
		fi
		engine "$root" release-notes --version "$REL_VERSION" --union "${files[@]}" --tag "$REL_TAG" "$@" || rc=$?
	fi
	rm -rf -- "${root:?}/$dir"
	return "$rc"
}

# rel_archive_add <branch> <parent> <count>: plan to set a branch aside: gives it a free 'unmerged'
# name and adds '<branch> TAB <new> TAB <parent> TAB <count>' to REL_ARCHIVE and the name to REL_PLANNED.
# Arguments: $1 the branch; $2 its nearest ORIGINAL; $3 the number of commits it has outside it.
# Returns: 0; 1 (after adding an error to REL_ERRORS) when no free name exists.
rel_archive_add() {
	local new
	new="$(archive_name "$1")" || {
		REL_ERRORS+=("no free name to set '$1' aside")
		return 1
	}
	REL_PLANNED="$REL_PLANNED$new"$'\n'
	REL_ARCHIVE+=("$1"$'\t'"$new"$'\t'"$2"$'\t'"$3")
}

# rel_check_branches <scope> [<extra branch> [<top>]]: after the branches of a tree are sorted into
# REL_OK and REL_ARCHIVE, fill REL_DELETE_REMOTE and REL_DELETE_LOCAL (the integrated ones, the old
# names of those set aside, the top) and add an error for every branch of the tree checked out in
# another worktree, because it cannot be deleted from here.
# Arguments: $1 the tree prefix ('<v>' or '<v>/<ot>'); $2 one more branch to protect (e.g. the
# mainline); $3 the top branch, deleted after the integrated ones (empty: the caller deletes it).
# Returns: 0.
rel_check_branches() {
	local scope="$1" extra="${2:-}" top="${3:-}" entry b here wt archived=$'\n' entries=()
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do archived="$archived${entry%%$'\t'*}"$'\n'; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"}; do entries+=("$entry"); done
	[ -z "$top" ] || entries+=("$top"$'\t')
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do entries+=("$entry"); done
	for entry in ${entries[@]+"${entries[@]}"}; do
		b="${entry%%$'\t'*}"
		exists_ref "refs/remotes/origin/$b" && REL_DELETE_REMOTE+=("$b")
		case "$archived" in *$'\n'"$b"$'\n'*) continue ;; esac # set aside: renamed locally instead
		exists_ref "refs/heads/$b" && REL_DELETE_LOCAL+=("$b")
	done
	here="$(git rev-parse --show-toplevel)"
	while IFS= read -r wt; do
		b="${wt#*$'\t'}"
		b="${b#refs/heads/}"
		if [[ $b == "$scope"/* || (-n $extra && $b == "$extra") ]]; then
			REL_ERRORS+=("'$b' is checked out in another worktree; switch it or remove that worktree")
		fi
	done < <(git worktree list --porcelain | awk -v h="$here" '/^worktree /{w=substr($0,10)} /^branch /{ if (w != h) print w "\t" $2 }')
	return 0
}

# rel_print_report <consistent message> <ok label>: the first part of the checks of a release
# preview: '## Checks', the consistent line when REL_ERRORS is empty, one '[!!]' line per error, one
# '[ok]' line per branch of REL_OK and one '[!!]' line per branch of REL_ARCHIVE.
# Arguments: $1 the text after '[ok] ' of the consistent line; $2 the text put before the ORIGINAL on
# each OK branch line ('contained in ' or ''). Returns: 0.
rel_print_report() {
	local entry b p n new e
	echo "## Checks"
	echo
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then echo "[ok] $1"; fi
	for e in ${REL_ERRORS[@]+"${REL_ERRORS[@]}"}; do echo "[!!] $e"; done
	for entry in ${REL_OK[@]+"${REL_OK[@]}"}; do
		IFS=$'\t' read -r b p <<<"$entry"
		echo "[ok] $b: $2$p"
	done
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new p n <<<"$entry"
		echo "[!!] $b: $n commit(s) not in $p -> will be set aside as $new"
	done
}
