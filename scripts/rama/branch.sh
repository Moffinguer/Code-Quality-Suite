#!/usr/bin/env bash
# rama/branch.sh - git np / git nr / git convertir-padre / git subir (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

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
	testing_reserved_segment "$seg" && die "'$seg' is reserved for the TESTING sandbox: git testing crear"
	special_refusal "$seg" >/dev/null && die "$(special_refusal "$seg")"
	case "$seg" in */*) die "the name is one segment (no '/'): $seg" ;; "$QS_BR_LEAF" | "$QS_BR_RELEASE_LEAF") die "'$seg' is reserved" ;; esac
	if [ "$MIGRACION" = 1 ]; then
		[ "$kind" = padre ] || die "--migracion only goes with a new version: git np <version> --migracion"
		special_enabled MIGRATION || die "MIGRATION is not enabled (it needs branches.flow: squash and branches.special.MIGRATION)"
	fi
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
	elif [ "$MIGRACION" = 1 ]; then
		die "--migracion goes only with a new version, from $QS_BR_MAINLINE: git np <version> --migracion (on a fresh '<version>/$QS_BR_LEAF': git migracion)"
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
	why="$(special_migration_lock "${new%%/*}" "$new")" && die "$why"
	taken "${new%/"$QS_BR_LEAF"}" && die "'${new%/"$QS_BR_LEAF"}' already exists (as a branch or a folder of branches)"
	base="$(best_ref "$cur")"
	base="${base:-$cur}"
	git branch -q --no-track "$new" "$base"
	# why: the version tree starts with its version written down, so every branch below inherits it
	[ "$cur" = "$QS_BR_MAINLINE" ] && version_commit "$new" "$seg"
	git checkout -q "$new"
	say "created '$new' from '$base' (parent: $(parent_branch "$new"))"
	qs_publish_new "$new"
	[ "$kind" = padre ] && say "children: git np <name> (parent) / git nr <name> (final)"
	[ "$MIGRACION" = 1 ] && mg_create "${new%%/*}"
	return 0
}

convert_branch() { # final branch '<F>/<x>' -> '<F>/<x>/ORIGINAL', local and on origin
	local cur="$1" new remote=0 sha pub=1
	is_mainline "$cur" && die "'$cur' is a mainline branch"
	is_parent_branch "$cur" && die "'$cur' is already a parent branch"
	valid_branch_name "$cur" >/dev/null || die "'$cur' does not follow the branch model"
	new="$cur/$QS_BR_LEAF"
	if has_origin && git ls-remote --exit-code --heads origin "refs/heads/$cur" >/dev/null 2>&1; then remote=1; fi
	qs_publish_on || pub=0
	if [ "$remote" = 1 ] && [ "$pub" = 0 ]; then
		echo "[rama] '$cur' exists on origin. Converting it deletes origin/$cur and pushes '$new'." >&2
		echo "       Anyone else with '$cur' must run: git fetch --prune && git checkout $new" >&2
		confirm "Continue?" || die "cancelled"
	fi
	# why: a branch that only exists on origin gets its local copy first, then the same rename
	exists_ref "refs/heads/$cur" || git branch -q --no-track "$cur" "origin/$cur"
	sha="$(git rev-parse -q --verify "refs/remotes/origin/$cur" || git rev-parse "refs/heads/$cur")"
	git branch -m "$cur" "$new"
	if [ "$remote" = 1 ] && [ "$pub" = 0 ]; then
		git push -q origin --delete "$cur"
		git push -q -u origin "$new"
	elif [ "$remote" = 1 ]; then
		# why: one atomic push under a lease on the old tip; the human is asked only when it is lost
		if qs_publish_rename "$cur" "$new" "$sha"; then
			echo "[rama] origin: '$cur' is now '$new'. Anyone else with '$cur' must run: git fetch --prune && git checkout $new" >&2
		else
			echo "[rama] WARN: origin was not changed: the local rename to '$new' is kept. Ask the human before touching origin/$cur (someone may have pushed to it)" >&2
		fi
	else
		qs_publish_new "$new"
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
	local cur parent base head resume=0 rc=0
	cur="$(current_branch || true)"
	if [ -z "$cur" ] && [ "${QS_BR_FLOW:-merge}" = squash ] && rebase_in_progress; then
		# why: publish_stopped tells the human to re-run git subir while the RELEASE rebase is stopped
		head="$(rebase_state head-name)"
		head="${head#refs/heads/}"
		if is_release_branch "$head"; then cur="$head" resume=1; fi
	fi
	[ -n "$cur" ] || die "detached HEAD"
	testing_refused "$cur" && exit 1 # TESTING sandbox guard
	si_subir_check "$cur" || rc=$?
	[ "$rc" != 1 ] || return 0 # CHECKPOINT: local, nothing to sync
	[ "$rc" = 0 ] || exit 1    # FORMAT: regenerated, never synced
	[ "$resume" = 1 ] || require_clean
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
			git push -q -u origin "$cur"
		}
	else
		base="$(best_ref "$parent")"
		[ -n "$base" ] || die "parent '$parent' not found locally or on origin"
		if [ "${QS_BR_FLOW:-merge}" = squash ] && is_release_branch "$cur"; then
			# why: '<v>/RELEASE' onto develop solves its release-file conflicts like git publicar
			REL_RELEASE="$cur" REL_VERSION="$(branch_version "$cur")" PUB_AGAIN="git subir"
			REL_TAG="$(git config "qs.release.$REL_VERSION.tag" 2>/dev/null || render_tag "$REL_VERSION/$QS_BR_LEAF")"
			# why: publish_autosolve writes the solved files by their path from the top
			cd "$(git rev-parse --show-toplevel)"
			if [ "$resume" = 1 ]; then
				say "resuming the rebase of $cur onto $QS_BR_MAINLINE..."
				publish_rebase "$(rebase_state onto)"
			else
				# why: the push below is forced; commits only origin has would be lost
				publish_local_release
			fi
			publish_rebase "$(git rev-parse "$base^{commit}")"
			git checkout -q "$cur"
		elif ! git merge-base --is-ancestor "$base" "$cur"; then
			say "rebasing $cur onto $base..."
			git rebase -q "$base" || die "conflicts: resolve, 'git rebase --continue', then re-run git subir (rerere remembers)"
		fi
		has_origin && {
			say "pushing $cur (--force-with-lease)..."
			git push -q -u --force-with-lease origin "$cur"
		}
	fi
	say "done."
}
