#!/usr/bin/env bash
# rama/integra.sh - git integra (rebase, merge, squash, messages) (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

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

# rebase_state <file>: the content of <file> (head-name, onto) of the rebase stopped in the current
# worktree, from rebase-merge or rebase-apply; nothing when no rebase is stopped.
# Arguments: $1 the state file name. Output: its content. Returns: 0.
rebase_state() {
	local gd
	gd="$(git rev-parse --absolute-git-dir)"
	cat "$gd/rebase-merge/$1" 2>/dev/null || cat "$gd/rebase-apply/$1" 2>/dev/null || true
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
	qs_ref_exists "refs/remotes/origin/$b" && where="locally and on origin"
	if ! confirm "delete the integrated '$b' $where?" 2>/dev/null; then
		say "kept '$b'. Delete it: git branch -D $b$(qs_ref_exists "refs/remotes/origin/$b" && echo " && git push origin --delete $b")"
		if qs_ref_exists "refs/remotes/origin/$b" && ! git merge-base --is-ancestor "refs/remotes/origin/$b" "$b"; then
			say "WARNING: '$b' was rebased and now diverges from origin/$b: a plain push is rejected."
			say "Update origin safely (pre-push needs the bypass: the branch is behind its parent now): QUALITY_SKIP_PARENT_CHECK=1 git push --force-with-lease origin $b"
			if confirm "run it now (force-with-lease)?" 2>/dev/null; then
				QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$b" || say "could not update '$b' on origin"
			fi
		fi
		return 0
	fi
	git branch -q -D "$b" || say "could not delete '$b' locally (checked out in another worktree?)"
	if qs_ref_exists "refs/remotes/origin/$b"; then
		git push -q origin --delete "$b" || say "could not delete '$b' on origin"
	fi
	say "deleted '$b' $where"
}

# migration_subject <subject>: the subject of the MIGRATION squash commit: a 'build' Conventional
# Commit ('build: x', 'build(scope): x', 'build!: x') as it is; a plain text gets the 'build: '
# prefix. Arguments: $1 the subject given with -m. Returns: 0 and prints the subject; 1 (after
# printing why on stderr) when it is a Conventional Commit of another type.
migration_subject() {
	local s="$1"
	if printf '%s' "$s" | grep -qE '^build(\([^)]*\))?!?: .'; then
		printf '%s' "$s"
	elif printf '%s' "$s" | grep -qE '^[a-z][a-z0-9-]*(\([^)]*\))?!?: '; then
		echo "[rama] the MIGRATION squash subject is 'build: <subject>' (or 'build!: <subject>'), not '$s'" >&2
		return 1
	else
		printf 'build: %s' "$s"
	fi
}

# integra_squash <branch> <parent>: git integra with branches.flow = squash. A final branch, or a
# '<F>/ORIGINAL' below the OT whose children are all integrated (--force: even when not), is
# rebased onto <parent> and lands there as ONE single-parent commit (message: subject and body
# from -m or the editor, Commits:, Files:, Norms:, Refs:, Squashed:); then it is deleted
# (confirmation unless --yes). Refused: '<v>/<ot>/ORIGINAL' and '<v>/ORIGINAL' (git release),
# <branch> or <parent> checked out in another worktree, nothing to integrate.
# MIGRATION: '<v>/MIGRATION' and '<v>/MIGRATION/ORIGINAL' (all children in) squash into '<v>/ORIGINAL'
# with the subject 'build: <subject>' (or 'build!:'); afterwards what is left under
# '<v>/MIGRATION/' goes (mg_after_squash) and '<v>/DOCS' is created in DOCS mode.
# Returns 0; exits through die when refused or on a conflict (nothing changed).
integra_squash() {
	local cur="$1" parent="$2" pending="" bypass=0 tpl editor subject text="" m mig=0 first=""
	# why: the MIGRATION branch of a version (or its folder) squashes into '<v>/ORIGINAL' as a build commit
	case "$cur" in "${cur%%/*}"/MIGRATION | "${cur%%/*}/MIGRATION/$QS_BR_LEAF") [ "$(special_kind "$cur")" = MIGRATION ] && mig=1 ;; esac
	if is_parent_branch "$cur"; then
		[ "$mig" = 1 ] || [ "$(branch_depth "$cur")" -ge 3 ] ||
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
	if [ "$mig" = 1 ]; then
		sed -i '1s/^feat([^)]*): DESCRIPCION_BREVE$/build: DESCRIPCION_BREVE/' "$tpl"
		[ "${#MSG[@]}" -eq 0 ] || first="$(migration_subject "${MSG[0]}")" || exit 1
	elif [ "${#MSG[@]}" -gt 0 ]; then first="${MSG[0]}"; fi
	if [ "${#MSG[@]}" -gt 0 ]; then
		# why: agents cannot drive an editor; their Norms: lines go into the Norms: trailer
		{
			printf '%s\n\n' "$first"
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
	if [ "$mig" = 1 ]; then
		printf '%s\n' "$subject" | grep -qE '^build(\([^)]*\))?!?: .' ||
			die "the MIGRATION squash subject is 'build: <subject>' (or 'build!: <subject>'); nothing was integrated ('$cur' is rebased onto '$parent')"
	fi
	say "$cur -> $parent (squash)"
	git checkout -q "$parent"
	if ! quiet_merge -c merge.ff=true merge -q --squash "$cur" || ! git commit -q --allow-empty --cleanup=strip -F "$tpl"; then
		git reset -q --hard HEAD
		git checkout -q "$cur"
		die "the squash commit into '$parent' failed (see above); '$parent' is unchanged"
	fi
	say "done: '$cur' integrated into '$parent' as $(git rev-parse --short HEAD). Push: git push origin $parent"
	squash_drop_child "$cur"
	# shellcheck disable=SC2086 # why: pending is a space separated list of branch names (no spaces)
	[ "$mig" = 0 ] || mg_after_squash "${cur%%/*}" $pending
	return 0
}

cmd_integra() {
	local cur parent base mode tpl tag depth unmerged="" c cref editor subject
	cur="$(current_branch)" || die "detached HEAD"
	testing_refused "$cur" && exit 1 # TESTING sandbox guard
	valid_branch_name "$cur" >/dev/null || die "'$cur' does not follow the branch model"
	is_mainline "$cur" && die "'$cur' is a mainline branch; nothing to integrate"
	parent="$(parent_branch "$cur")"
	[ -n "$parent" ] || die "'$cur' has no parent"
	si_integra_refuse "$cur" "$parent" || exit 1 # SPIKE, ATTEMPT, REVIEW, QUARANTINE, CHECKPOINT never go up
	require_clean
	fetch_origin
	flow_guard_integra "$cur" "$parent" || exit 1 # FG2/FG3: wrong flow or generated rules file
	if ! qs_ref_exists "refs/heads/$parent"; then
		qs_ref_exists "refs/remotes/origin/$parent" || die "parent '$parent' does not exist (create it with git np)"
		git branch -q "$parent" "origin/$parent"
	elif qs_ref_exists "refs/remotes/origin/$parent" && git merge-base --is-ancestor "$parent" "origin/$parent"; then
		git branch -q -f "$parent" "origin/$parent" 2>/dev/null || true # fast-forward the local parent
	fi
	if [ "${QS_BR_FLOW:-merge}" = squash ]; then
		si_integra_order "$cur" "$parent" || exit 1
		integra_squash "$cur" "$parent"
		si_drop_task_extras "$cur"
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
			if qs_ref_exists "refs/tags/$tag"; then
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
	is_parent_branch "$cur" || say "the final branch can go: git branch -d $cur$(qs_ref_exists "refs/remotes/origin/$cur" && echo " && git push origin --delete $cur")"
}
