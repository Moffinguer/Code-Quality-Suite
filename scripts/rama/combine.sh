#!/usr/bin/env bash
# rama/combine.sh - git combinar (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

# --- git combinar --------------------------------------------------------------------------------
# State of one run, set by cmd_combinar: CB_BASE the develop commit, CB_GD the state folder, CB_WT
# the temporary worktree. Helpers return through CB_* variables when a subshell would lose them.
# CB_ARCHIVE holds "<branch><TAB><archive name><TAB><tip>" per combined RELEASE; CB_ROLLBACK is 1
# while the local branches are being moved (CB_HEAD_REF / CB_HEAD_SHA: where HEAD was); CB_PWD and
# CB_PREV_TRAP are restored when the run ends.
CB_BASE="" CB_GD="" CB_WT="" CB_REL="" CB_ONLY="" CB_OUT="" CB_CONFLICTS="" CB_FILES=""
CB_N=0 CB_M=0 CB_K=0 CB_J=0
CB_ARCHIVE=() CB_ROLLBACK=0 CB_HEAD_REF="" CB_HEAD_SHA="" CB_PWD="" CB_PREV_TRAP=""
# flow = squash: CB_UNION holds "<version><TAB><tip>" per combined RELEASE, oldest first (the
# sections the new entry unites); CB_TAGS "<tag><TAB><object>" per local version tag that git
# release put on a combined RELEASE tip (deleted with the branches: that version is never published)
CB_UNION=() CB_TAGS=()

# combine_union_notes [--write]: the CHANGELOG.md entry of the combined version with branches.flow
# = squash: qs.py release-notes --union over the '## <v>' section of each combined RELEASE, read on
# its tip (the reviewed text), in CB_UNION order. The inputs are written to a scratch folder of the
# work tree (the engine sees only the work tree) and removed afterwards.
# Arguments: extra options of release-notes (--write merges the entry into CHANGELOG.md); reads
# REL_VERSION (the combined version) and REL_TAG. Returns: the exit status of the engine.
combine_union_notes() {
	rel_union_notes combine_union_inputs "$@"
}

# combine_union_inputs <root> <dir>: write the inputs of combine_union_notes into <dir>: the '## <v>'
# section of each combined RELEASE, in CB_UNION order. Called by rel_union_notes, whose array 'files'
# it fills. Arguments: $1 work tree root; $2 scratch folder, relative to it. Returns: 0.
combine_union_inputs() {
	local root="$1" dir="$2" entry v t i=0
	for entry in ${CB_UNION[@]+"${CB_UNION[@]}"}; do
		IFS=$'\t' read -r v t <<<"$entry"
		i=$((i + 1))
		REL_VERSION="$v" version_section "$t" >"$root/$dir/$(printf '%02d' "$i").md"
		files+=("$dir/$(printf '%02d' "$i").md")
	done
	return 0
}

# combine_source_tags <branch> <tip>: with branches.flow = squash, add to CB_TAGS the local tag git
# release put on the tip of a combined '<v>/RELEASE' (qs.release.<v>.tag, else the tag template),
# when it points at <tip>. Arguments: $1 the RELEASE branch; $2 its tip. Returns: 0.
combine_source_tags() {
	local v tag
	[ "${QS_BR_FLOW:-merge}" = squash ] || return 0
	v="$(branch_version "$1")"
	tag="$(git config "qs.release.$v.tag" 2>/dev/null || render_tag "$v/$QS_BR_LEAF")"
	exists_ref "refs/tags/$tag" && [ "$(git rev-parse "refs/tags/$tag^{commit}")" = "$2" ] || return 0
	CB_TAGS+=("$tag"$'\t'"$(git rev-parse "refs/tags/$tag")")
}

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
		if qs_ref_exists "$s^{commit}"; then
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

# combine_contains <later> <earlier>: whether a RELEASE already holds the work of another one it
# shares no squashed history with, so the earlier one must not be squashed again (a RELEASE built
# on the earlier one keeps its own squash: see combine_counts). True when the earlier tip is not
# an ancestor of the later and either every own commit of the earlier one that the later lacks
# (not in develop; no release commit, no mainline merge) is named in a message of the later
# history (the 'Commits:' list of the squash that merged it in), or the two share no history
# beyond develop and applying the earlier one's changes on the later one merges cleanly and
# changes nothing.
# Arguments: $1 the later tip; $2 the earlier tip. Exit status: 0 when contained, 1 otherwise.
combine_contains() {
	local later="$1" earlier="$2" h s mb out bodies="" n=0
	if git merge-base --is-ancestor "$earlier" "$later"; then return 1; fi
	bodies="$(git log --format=%B "$later" "^$CB_BASE" --)"
	while IFS=$'\x1f' read -r h s; do
		combine_mainline_merge "$h" && continue
		[[ $s =~ $RELEASE_COMMITS_RX ]] && continue
		git merge-base --is-ancestor "$h" "$later" && continue
		grep -q -- "^- ${h:0:7}" <<<"$bodies" || {
			n=-1
			break
		}
		n=$((n + 1))
	done < <(git log --format='%H%x1f%s' "$earlier" "^$CB_BASE" --)
	[ "$n" -gt 0 ] && return 0
	mb="$(git merge-base "$earlier" "$later" | sed -n 1p)"
	if [ -n "$mb" ] && ! git merge-base --is-ancestor "$mb" "$CB_BASE"; then return 1; fi
	mb="$(git merge-base "$earlier" "$CB_BASE" | sed -n 1p)"
	[ -n "$mb" ] || return 1
	out="$(git merge-tree --write-tree --no-messages "--merge-base=$mb" "$later" "$earlier" 2>/dev/null)" || return 1
	[ "$(sed -n 1p <<<"$out")" = "$(git rev-parse "$later^{tree}")" ]
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
# (a combined RELEASE) contributes its own list. Then the Files: block in CB_FILES (flow = squash;
# empty otherwise) and the 'Squashes:' lines.
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
	[ -z "$CB_FILES" ] || printf '%s\n\n' "$CB_FILES"
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
	REL_PLANNED=$'\n' CB_ARCHIVE=() CB_TAGS=()
	while [ "$#" -ge 2 ]; do
		b="$1"
		new="$(archive_name "$b")" || die "no free name to set '$b' aside; nothing was changed"
		REL_PLANNED="$REL_PLANNED$new"$'\n'
		CB_ARCHIVE+=("$b"$'\t'"$new"$'\t'"$2")
		combine_source_tags "$b" "$2"
		if exists_ref "refs/heads/$b"; then echo "  local:  $b -> $new"; else echo "  local:  $new (copy of origin/$b)"; fi
		if has_origin && exists_ref "refs/remotes/origin/$b"; then
			echo "  origin: $b -> $new  (renamed on origin: $b is deleted there)"
		fi
		shift 2
	done
	for b in ${CB_TAGS[@]+"${CB_TAGS[@]}"}; do echo "  local:  tag ${b%%$'\t'*} deleted (that version is published as part of the combined one)"; done
	echo "  local:  $REL_RELEASE $(if exists_ref "refs/heads/$REL_RELEASE"; then echo "moves to the combined result"; else echo "created"; fi)"
	if has_origin; then echo "  origin: $REL_RELEASE pushed; all origin changes in one atomic push, at the end"; fi
}

# combine_apply <result>: move the local branches in one transaction (git update-ref --stdin):
# REL_RELEASE to the result, each CB_ARCHIVE entry renamed, each CB_TAGS tag deleted (flow =
# squash: the local tags of the combined versions), then check out REL_RELEASE. HEAD is
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
	for entry in ${CB_TAGS[@]+"${CB_TAGS[@]}"}; do
		IFS=$'\t' read -r b t <<<"$entry"
		printf 'delete refs/tags/%s %s\n' "$b" "$t" >>"$tx"
		printf 'create refs/tags/%s %s\n' "$b" "$t" >>"$undo.new"
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
	local target="" incl="" held="" rels=() chosen=() ordered=() done_tips=() cp_tips=() links=() r t c d cp src bad=0 covered after
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
		--contenida | --contained)
			held="${2:?$1 needs versions}"
			shift
			;;
		--contenida=* | --contained=*) held="${1#*=}" ;;
		*) die "unknown argument '$1' (combinar: --version <v>, --incluir <v1,v2...>, --contenida <v1,v2...>, --yes)" ;;
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
		# why: a later RELEASE that already holds this one (merged in and squashed, or the same
		# changes) would squash it a second time and conflict with itself: it is not applied again
		covered=""
		after=0
		for c in "${ordered[@]}"; do
			if [ "$c" = "$r" ]; then
				after=1
			elif [ "$after" = 1 ] && { combine_contains "${tip[$c]}" "$t" || case ",$held," in *",$(branch_version "$r"),"* | *",$r,"*) true ;; *) false ;; esac } then
				covered="$c"
				break
			fi
		done
		if [ -n "$covered" ]; then
			say "$r: already contained in $covered; not squashed again"
			done_tips+=("$t")
			if [ -n "${orig[$r]}" ]; then
				while read -r b c; do
					done_tips+=("$c")
					links+=("$c")
				done <<<"${orig[$r]}"
			fi
			links+=("$t")
			CB_UNION+=("$(branch_version "$r")"$'\t'"$t")
			continue
		fi
		combine_paths "$t"
		only="$CB_ONLY"
		btree="$(git rev-parse "$CB_BASE^{tree}")"
		cp="$(combine_copy_point "$t" ${cp_tips[@]+"${cp_tips[@]}"})"
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
				CB_FILES=""
				# why: with flow = squash every commit carries its Files: block, the squashes too
				[ "${QS_BR_FLOW:-merge}" != squash ] || CB_FILES="$(squash_files_block "$h" "$tree")"
				combine_message "$(branch_version "$r")" "$t" "$sq" ${done_tips[@]+"${done_tips[@]}"} >"$CB_GD/combine.msg"
				# why: the squash keeps the creation date of what it squashes (the order of a later combinar)
				h="$(GIT_AUTHOR_DATE="${okey[$r]%%$'\t'*} +0000" git commit-tree "$tree" -p "$h" -F "$CB_GD/combine.msg")"
				made=1
			fi
			git -C "$CB_WT" reset -q --hard "$h"
		fi
		say "$r: $CB_N own commit(s) squashed; dropped $CB_M mainline merge(s), $CB_K release commit(s), $CB_J already combined$([ "$made" = 1 ] || echo "; nothing new, no squash commit")"
		done_tips+=("$t")
		cp_tips+=("$t")
		if [ -n "${orig[$r]}" ]; then
			while read -r b c; do
				done_tips+=("$c")
				cp_tips+=("$c")
				links+=("$c")
			done <<<"${orig[$r]}"
		fi
		links+=("$t")
		CB_UNION+=("$(branch_version "$r")"$'\t'"$t")
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
	# why: flow = squash: the entry is the union of the reviewed sections of the combined RELEASEs
	[ "${QS_BR_FLOW:-merge}" != squash ] || REL_UNION=combine
	release_commits
	REL_UNION=0
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
		# why: a stopped git publicar of a combined RELEASE left its origin tip; that RELEASE is gone
		git config --unset-all "qs.publish.$(branch_version "$r").from" 2>/dev/null || true
	done
	git config --unset-all "qs.publish.$target.from" 2>/dev/null || true
	for c in "${CB_ARCHIVE[@]}"; do say "${c%%$'\t'*} kept as $(cut -f2 <<<"$c")"; done
	# 10. origin last, in one atomic push
	combine_push
	combine_finish
	say "combined ${#chosen[@]} release(s) into $REL_RELEASE; RELEASE branches now: $(release_branches | tr '\n' ' ')"
	echo "Review $QS_BR_CHANGELOG on $REL_RELEASE, then: git publicar --version $target"
}
