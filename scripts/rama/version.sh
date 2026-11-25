#!/usr/bin/env bash
# rama/version.sh - git nueva-version and the version release (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

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
	why="$(special_migration_lock "$v" "$v/$QS_BR_LEAF")" && die "$why"
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
				'index($0, p) == 1 && $0 != t && $0 != r { print "C\t" $0 }' |
				while IFS=$'\t' read -r a b; do # why: special branches belong to one version
					if [ -z "$(special_kind "$b")" ]; then printf '%s\t%s\n' "$a" "$b"; fi
				done
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
	qs_publish_new "${made[@]}"
	return 0
}

# version_cfg <key> [<value>]: read (one argument) or write a progress key qs.release.<v>.<key> of
# REL_VERSION. Arguments: $1 key, $2 value to store. Returns: 0; prints the value when reading
# (nothing when unset).
version_cfg() {
	if [ "$#" -ge 2 ]; then
		git config "qs.release.$REL_VERSION.$1" "$2"
	else
		git config "qs.release.$REL_VERSION.$1" 2>/dev/null || true
	fi
}

# version_state_keys: print the set git config keys qs.release.<v>.<key> of REL_VERSION, one per
# line. The subsection must end right after <v>: version 5 never matches the keys of 5.0.0-RC1.
# Arguments: none. Returns: 0 (nothing printed when the version has no state).
version_state_keys() {
	git config --local --name-only --list 2>/dev/null | LC_ALL=C sort -u |
		awk -v p="qs.release.$REL_VERSION." 'index($0, p) == 1 && substr($0, length(p) + 1) !~ /\./' || true
	return 0
}

# version_state_names: the key names of version_state_keys without the prefix (plan ots current
# tag), space separated. Arguments: none. Returns: 0.
version_state_names() {
	local k names=""
	while IFS= read -r k; do
		if [ -n "$k" ]; then names="$names ${k##*.}"; fi
	done < <(version_state_keys)
	printf '%s' "${names# }"
	return 0
}

# version_cfg_clear: forget the whole resume state of REL_VERSION: plan, ots, current and the tag
# name (qs.release.<v>.tag). Used when <v>/RELEASE is gone (an abandoned release) and by git release
# --reset. The tag itself (refs/tags) is never deleted here. Arguments: none. Returns: 0.
version_cfg_clear() {
	local k
	while IFS= read -r k; do
		if [ -n "$k" ]; then git config --unset-all "$k" 2>/dev/null || true; fi
	done < <(version_state_keys)
	return 0
}

# version_progress_clear: forget the progress of a version release (plan, ots, current) once
# <v>/RELEASE is prepared. The tag name stays: git publicar reads it and clears it on success.
# Arguments: none. Returns: 0.
version_progress_clear() {
	local k
	for k in plan ots current; do git config --unset-all "qs.release.$REL_VERSION.$k" 2>/dev/null || true; done
	return 0
}

# version_forget_stale: when '<v>/RELEASE' does not exist and no rebase is stopped, the resume state
# left by an abandoned release (its RELEASE deleted by hand) is stale: it is cleared, the tag name
# too, and the tag name is computed again unless it was given on the command line. Says so when it
# clears something. Arguments: none; reads REL_VERSION REL_TAG_GIVEN. Returns: 0.
version_forget_stale() {
	local names
	exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF" && return 0
	rebase_in_progress && return 0
	names="$(version_state_names)"
	[ -n "$names" ] || return 0
	version_cfg_clear
	if [ "$REL_TAG_GIVEN" = 0 ]; then
		REL_TAG="$(render_tag "$REL_VERSION/$QS_BR_LEAF")"
		REL_TAG_AT=""
		if exists_ref "refs/tags/$REL_TAG"; then REL_TAG_AT="$(git rev-parse "refs/tags/$REL_TAG^{commit}")"; fi
	fi
	say "$REL_VERSION/$QS_BR_RELEASE_LEAF is gone: the stale release state of $REL_VERSION is cleared ($names)"
	return 0
}

# version_reset: git release --reset --version <v>: forget the release state of REL_VERSION
# (version_cfg_clear) after a confirmation (--yes skips it). Refused, nothing changed, while a rebase
# is stopped or '<v>/RELEASE' exists: that branch is the release in progress or prepared, and git
# publicar needs the tag name it keeps. A local tag is kept (git tag -d deletes it).
# Arguments: none; reads REL_VERSION REL_TAG. Returns: 0; exits through die when refused or cancelled.
version_reset() {
	local names
	! rebase_in_progress || die "a rebase is stopped: finish it (git rebase --continue) or give it up (git rebase --abort) first"
	! exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF" ||
		die "'$REL_VERSION/$QS_BR_RELEASE_LEAF' exists: the release is in progress or prepared; publish it (git publicar --version $REL_VERSION) or delete that branch by hand first; nothing was changed"
	names="$(version_state_names)"
	if [ -z "$names" ]; then
		say "nothing to reset: no release state for $REL_VERSION"
		return 0
	fi
	confirm "Forget the release state of $REL_VERSION ($names)?" || die "cancelled; nothing was changed"
	version_cfg_clear
	say "release state of $REL_VERSION forgotten ($names)"
	if exists_ref "refs/tags/$REL_TAG"; then say "tag $REL_TAG is kept (git tag -d $REL_TAG deletes it)"; fi
	return 0
}

# version_ot_order <ot>...: the OTs sorted oldest first: by the author date of the oldest own
# non-merge commit of '<v>/<ot>/RELEASE' (since REL_TIP, the version ORIGINAL), then by name.
# Arguments: the OTs. Returns: 0; prints one OT per line.
version_ot_order() {
	local o tip key
	for o in "$@"; do
		tip="$(best_ref "$REL_VERSION/$o/$QS_BR_RELEASE_LEAF" || true)"
		key=""
		[ -z "$tip" ] || key="$(git log --no-merges --format=%at "$tip" "^$REL_TIP" -- | LC_ALL=C sort -n | head -n1)"
		printf '%s\t%s\n' "${key:-9999999999}" "$o"
	done | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2
}

# version_release_analyse: analyse the version REL_VERSION for its release (flow = squash). Fills
# REL_TOP REL_RELEASE REL_TIP REL_BASE REL_CL_BASE REL_ERRORS REL_OK REL_ARCHIVE REL_DELETE_LOCAL
# REL_DELETE_REMOTE REL_PLANNED REL_RESUME like release_analyse, plus REL_VOTS (the OTs, in rebase
# order) and REL_MISSING (the OTs that block the release, '<ot>: <why>'). On a resumed release
# ('<v>/RELEASE' exists and qs.release.<v>.plan is set) the OT list comes from the plan, because the
# OT RELEASEs may be gone; a plan without '<v>/RELEASE' is stale and ignored.
# Errors: no or diverged '<v>/ORIGINAL', develop missing, diverged or not inside it, an OT without
# RELEASE or with other branches, no OT at all, a stale '<v>/RELEASE', the tag on another commit, a
# branch of the version checked out in another worktree. Branches directly under '<v>/' (finals,
# '<v>/TESTING') are deleted when integrated (or clean) and set aside otherwise.
# Arguments: none. Returns: 0.
version_release_analyse() {
	local v="$REL_VERSION" o b p tb tp n rel others plan rt
	REL_TOP="$v/$QS_BR_LEAF" REL_RELEASE="$v/$QS_BR_RELEASE_LEAF"
	REL_ERRORS=() REL_OK=() REL_ARCHIVE=() REL_DELETE_LOCAL=() REL_DELETE_REMOTE=() REL_PLANNED=$'\n'
	REL_VOTS=() REL_MISSING=() REL_TIP="" REL_BASE="" REL_CL_BASE="" REL_RESUME=0
	if ! exists_branch "$REL_TOP"; then
		REL_ERRORS+=("'$REL_TOP' does not exist (git arbol $v)")
		return 0
	fi
	REL_TIP="$(branch_tip "$REL_TOP")"
	[ "$REL_TIP" = diverged ] && REL_ERRORS+=("$REL_TOP: local and origin diverged; run git subir on it first")
	REL_BASE="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$REL_BASE" ] || REL_ERRORS+=("'$QS_BR_MAINLINE' does not exist")
	if [ -n "$REL_BASE" ] && [ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ]; then
		REL_ERRORS+=("$QS_BR_MAINLINE: local and origin diverged; pull it first")
	fi
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		REL_CL_BASE="$REL_BASE"
		git merge-base --is-ancestor "$REL_BASE" "$REL_TIP" ||
			REL_ERRORS+=("$QS_BR_MAINLINE has $(git rev-list --count "$REL_TIP..$REL_BASE") commit(s) that $REL_TOP lacks; bring them in first: git checkout $REL_TOP && git subir")
	fi
	# why: the plan is the state of a release in progress; without '<v>/RELEASE' it is stale
	plan=""
	exists_branch "$REL_RELEASE" && plan="$(version_cfg plan)" || true
	if [ -n "$plan" ]; then
		REL_RESUME=1
		read -r -a REL_VOTS <<<"$plan"
	else
		while IFS= read -r o; do
			[ -n "$o" ] || continue
			rel="$v/$o/$QS_BR_RELEASE_LEAF"
			others="$(all_branches | awk -v p="$v/$o/" -v r="$rel" 'index($0, p) == 1 && $0 != r' | tr '\n' ' ')"
			if ! exists_branch "$rel"; then
				REL_MISSING+=("$o: no $rel (git release --ot $v/$o)")
			elif [ -n "$others" ]; then
				REL_MISSING+=("$o: still has branches: ${others% }")
			elif [ "$(branch_tip "$rel")" = diverged ]; then
				REL_MISSING+=("$o: $rel diverged between local and origin; pull it first")
			else
				REL_VOTS+=("$o")
			fi
		done < <(version_ots "$v")
		for o in ${REL_MISSING[@]+"${REL_MISSING[@]}"}; do REL_ERRORS+=("OT $o"); done
		if [ "${#REL_MISSING[@]}" -eq 0 ] && [ "${#REL_VOTS[@]}" -eq 0 ]; then
			REL_ERRORS+=("$v has no OT ('$v/<ot>/RELEASE'): nothing to release")
		fi
		if exists_branch "$REL_RELEASE"; then
			REL_ERRORS+=("'$REL_RELEASE' exists but no version release of $v is in progress (left by an earlier release?); publish or delete it first")
		fi
		if [ "${#REL_VOTS[@]}" -gt 1 ] && [ "$REL_TIP" != diverged ] && [ -n "$REL_TIP" ]; then
			mapfile -t REL_VOTS < <(version_ot_order "${REL_VOTS[@]}")
		fi
	fi
	if [ -n "$REL_TAG_AT" ]; then
		rt="$(best_ref "$REL_RELEASE" || true)"
		if [ "$REL_RESUME" = 0 ] || [ -z "$rt" ] || [ "$REL_TAG_AT" != "$(git rev-parse "$rt")" ]; then
			REL_ERRORS+=("tag '$REL_TAG' already exists on another commit; choose another name")
		fi
	fi
	# branches directly under the version: finals and the version TESTING sandbox
	while IFS= read -r b; do
		[ -n "$b" ] && [ "$b" != "$REL_TOP" ] && [ "$b" != "$REL_RELEASE" ] || continue
		[ "$(awk -F/ '{ print NF }' <<<"$b")" = 2 ] || continue
		tb="$(branch_tip "$b")"
		p="$REL_TOP"
		tp="$REL_TIP"
		if [ "$tb" = diverged ] || [ "$tp" = diverged ]; then
			REL_ERRORS+=("$([ "$tb" = diverged ] && echo "$b" || echo "$p"): local and origin diverged; run git subir on it first")
			continue
		fi
		if is_testing_branch "$b"; then
			if ot_testing_clean "$b"; then
				REL_OK+=("$b"$'\t'"$p (TESTING sandbox, nothing left to distribute)")
				continue
			fi
		elif ot_branch_in "$b" "$p"; then
			REL_OK+=("$b"$'\t'"$p")
			continue
		fi
		n="$(git rev-list --count --no-merges "$tp..$tb")"
		rel_archive_add "$b" "$p" "$n" || continue
	done < <(all_branches | awk -v p="$v/" 'index($0, p) == 1')
	for o in ${REL_VOTS[@]+"${REL_VOTS[@]}"}; do REL_OK+=("$v/$o/$QS_BR_RELEASE_LEAF"$'\t'"$REL_RELEASE (rebased into it)"); done
	rel_check_branches "$v"
	return 0
}

# version_section <rev>: the '## <v>' section of QS_BR_CHANGELOG at <rev> (REL_VERSION), heading
# included, as Common Changelog writes it ('## [<v>] - date' or '## <v> - date').
# Arguments: $1 revision. Returns: 0; prints nothing when the file or the section is missing.
version_section() {
	[ -n "$QS_BR_CHANGELOG" ] && git cat-file -e "$1:$QS_BR_CHANGELOG" 2>/dev/null || return 0
	git show "$1:$QS_BR_CHANGELOG" | tr -d '\r' | awk -v v="$REL_VERSION" '
		/^## / { if (on) exit; on = (index($0, "## [" v "]") == 1 || index($0, "## " v " ") == 1 || $0 == "## " v) }
		on { print }'
}

# version_union_notes [--write]: the CHANGELOG.md entry of the version release: qs.py release-notes
# --union over the section of each OT, read on its '<v>/<ot>/RELEASE' tip (the reviewed text), in
# REL_VOTS order, after the section of the direct commits of '<v>/ORIGINAL' since develop (changes
# without OT, warned by the engine) when there are any. The inputs are written to a scratch folder
# of the work tree (the engine sees only the work tree) and removed afterwards.
# Arguments: extra options of release-notes (--write merges the entry into CHANGELOG.md).
# Returns: the exit status of the engine; 1 when the suite image cannot run.
version_union_notes() {
	rel_union_notes version_union_inputs "$@"
}

# version_union_inputs <root> <dir>: write the inputs of version_union_notes into <dir>: the section
# of the direct commits, then the section of each OT RELEASE. Called by rel_union_notes, whose arrays
# 'files' and variable 'rc' it fills (rc=1 when the engine could not run).
# Arguments: $1 work tree root; $2 scratch folder, relative to it. Returns: 0.
version_union_inputs() {
	local root="$1" dir="$2" rel o i=0
	if engine "$root" release-notes --version "$REL_VERSION" --tip "$REL_TIP" --base "$REL_CL_BASE" \
		--tag "$REL_TAG" >"$root/$dir/00-direct.md"; then
		grep -q '^### ' "$root/$dir/00-direct.md" && files+=("$dir/00-direct.md")
	else rc=1; fi
	for o in ${REL_VOTS[@]+"${REL_VOTS[@]}"}; do
		i=$((i + 1))
		rel="$(best_ref "$REL_VERSION/$o/$QS_BR_RELEASE_LEAF" || true)"
		if [ -z "$rel" ]; then
			echo "[rama] WARN: $REL_VERSION/$o/$QS_BR_RELEASE_LEAF is gone: its section is not in the entry" >&2
			continue
		fi
		version_section "$rel" >"$root/$dir/$(printf '%02d' "$i")-$o.md"
		files+=("$dir/$(printf '%02d' "$i")-$o.md")
	done
	return 0
}

# version_rebase_done <ot>: record that the commits of OT <ot> are in '<v>/RELEASE'.
# Arguments: $1 OT. Returns: 0.
version_rebase_done() {
	version_cfg ots "$(version_cfg ots) $1"
	git config --unset "qs.release.$REL_VERSION.current" 2>/dev/null || true
}

# version_squash_message <ot> <rel> <base> <tip> <file>: write the message of the squash commit of
# an OT into '<v>/RELEASE': a subject, the OT and its ref, the Files: block of base..tip and the
# trailer 'Squashed: <ot RELEASE> <sha>'. Arguments: $1 OT, $2 OT RELEASE branch, $3 base commit,
# $4 OT RELEASE tip, $5 output file. Returns: 0.
version_squash_message() {
	local o="$1" rel="$2" base="$3" tip="$4" out="$5" tag
	tag="$(render_ot_ref "$REL_VERSION/$o")"
	{
		echo "chore(ot): OT $o of $REL_VERSION"
		echo ""
		echo "Release of OT $o ($rel)${tag:+, ref $tag}, brought in as one commit."
		echo ""
		squash_files_block "$base" "$tip"
		echo ""
		echo "Squashed: $rel $tip"
	} >"$out"
}

# version_squash_commit <msgfile> <parent>: commit the staged squash of an OT on the detached HEAD
# with plumbing (git commit-tree + reset): the work was gated on its own branches, so no hook runs
# again over thousands of lines (the rebase it replaces ran none either). Moves HEAD to the commit.
# Arguments: $1 message file, $2 parent commit. Returns: 0; ends the script when git fails (set -e).
version_squash_commit() {
	local tree c
	tree="$(git write-tree)"
	c="$(git commit-tree "$tree" -p "$2" -F "$1")"
	git reset -q --hard "$c"
}

# version_rebase_ot <ot>: put the work of '<v>/<ot>/RELEASE' on top of '<v>/RELEASE' as ONE squash
# commit: the tree difference of the OT RELEASE against its base, applied (git merge --squash, on a
# detached HEAD) onto the '<v>/RELEASE' tip, never its individual commits (the OT history may hold
# merge commits). CHANGELOG.md is kept as '<v>/RELEASE' has it: the union entry is written later
# from the OT sections. Skipped when the OT is already done (qs.release.<v>.ots); after a conflict
# solved by hand and committed the result is taken as it is (qs.release.<v>.current: '<ot> <RELEASE
# sha> <OT RELEASE sha>'). Then '<v>/RELEASE' moves to the result.
# Arguments: $1 OT; reads REL_VERSION REL_TIP REL_RELEASE. Returns: 0; exits through die on a
# conflict (with the instructions) or a failed merge.
version_rebase_ot() {
	local o="$1" rel cur onto tip head c msg base gd
	case " $(version_cfg ots) " in *" $o "*) return 0 ;; esac
	rel="$REL_VERSION/$o/$QS_BR_RELEASE_LEAF"
	onto="$(git rev-parse "refs/heads/$REL_RELEASE")"
	gd="$(git rev-parse --absolute-git-dir)"
	cur="$(version_cfg current)"
	if [ "${cur%% *}" = "$o" ]; then
		read -r _ c tip <<<"$cur"
		if [ "$c" != "$onto" ]; then # RELEASE already moved: only the record was missing
			version_rebase_done "$o"
			return 0
		fi
		head="$(git rev-parse -q --verify HEAD || true)"
		if [ -z "$(current_branch || true)" ] && [ -n "$head" ] && [ "$head" != "$onto" ] && [ "$head" != "$tip" ] &&
			git merge-base --is-ancestor "$onto" "$head"; then # committed by hand after the conflict
			git update-ref "refs/heads/$REL_RELEASE" "$head" "$onto"
			version_rebase_done "$o"
			say "OT $o: the squash finished by hand is now on $REL_RELEASE"
			return 0
		fi
		if [ -z "$(current_branch || true)" ] && [ "$head" = "$onto" ] && [ -f "$gd/SQUASH_MSG" ]; then
			[ -z "$(git diff --name-only --diff-filter=U)" ] ||
				die "OT $o still has conflicts. Solve them: edit the files, git add them, git commit (the message is ready); then run git release --version $REL_VERSION again: it resumes with the next OT. To start this OT again: git reset --hard $REL_RELEASE"
			version_squash_commit "$gd/SQUASH_MSG" "$onto"
			git update-ref "refs/heads/$REL_RELEASE" "$(git rev-parse HEAD)" "$onto"
			version_rebase_done "$o"
			return 0
		fi
	fi
	tip="$(git rev-parse "$(best_ref "$rel")")" || die "'$rel' is gone; the version release cannot go on (git config --get qs.release.$REL_VERSION.plan)"
	base="$(git merge-base "$onto" "$tip")" || die "'$rel' has nothing in common with $REL_RELEASE"
	version_cfg current "$o $onto $tip"
	say "squashing $rel into $REL_RELEASE..."
	git checkout -q --detach "$onto"
	msg="$gd/SQUASH_MSG"
	git merge --squash --ff -q "$tip" >/dev/null || [ -n "$(git diff --name-only --diff-filter=U)" ] || die "the squash of $rel into $REL_RELEASE failed (see above); $REL_AGAIN"
	# why: the changelog is rebuilt from the OT sections, never merged line by line
	if git cat-file -e "$onto:$QS_BR_CHANGELOG" 2>/dev/null; then
		git checkout -q "$onto" -- "$QS_BR_CHANGELOG"
	else git rm -q -f --ignore-unmatch -- "$QS_BR_CHANGELOG"; fi
	version_squash_message "$o" "$rel" "$base" "$tip" "$msg"
	if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
		die "conflict while squashing OT $o into $REL_RELEASE, in: $(git diff --name-only --diff-filter=U | tr '\n' ' '). Solve it: edit the files, git add them, git commit (the message is ready); then run git release --version $REL_VERSION again: it resumes with the next OT. To start this OT again: git reset --hard $REL_RELEASE"
	fi
	if git diff --cached --quiet; then
		rm -f "$msg"
		git reset -q --hard "$onto"
		version_rebase_done "$o"
		say "OT $o: nothing to bring in ($REL_RELEASE already has it)"
		return 0
	fi
	version_squash_commit "$msg" "$onto"
	rm -f "$msg"
	head="$(git rev-parse HEAD)"
	git update-ref "refs/heads/$REL_RELEASE" "$head" "$onto"
	version_rebase_done "$o"
	say "OT $o: 1 squash commit on $REL_RELEASE"
}

# version_tag_message <file>: write the message of the version tag: 'Release <tag> (<v>)', a blank
# line and the body of the '## <v>' entry of QS_BR_CHANGELOG on '<v>/RELEASE'.
# Arguments: $1 output file. Returns: 0.
version_tag_message() {
	{
		echo "Release $REL_TAG ($REL_VERSION)"
		echo
		version_section "refs/heads/$REL_RELEASE" | sed '1d' | sed '/./,$!d'
	} >"$1"
}

# version_tag_create: the annotated tag REL_TAG on the '<v>/RELEASE' tip, message = its CHANGELOG.md
# entry (version_tag_message); local only, git publicar pushes it. Nothing when it is already there.
# Arguments: none. Returns: 0; exits through die when the tag cannot be created.
version_tag_create() {
	local msg tip
	tip="$(git rev-parse "refs/heads/$REL_RELEASE")"
	if exists_ref "refs/tags/$REL_TAG"; then
		[ "$(git rev-parse "refs/tags/$REL_TAG^{commit}")" = "$tip" ] && return 0
		die "tag '$REL_TAG' exists on another commit; nothing was pushed or deleted. Delete it (git tag -d $REL_TAG) and run git release again"
	fi
	msg="$(git rev-parse --absolute-git-dir)/quality-suite/RELEASE_TAG_MSG"
	mkdir -p "$(dirname "$msg")"
	version_tag_message "$msg"
	git tag -a --cleanup=whitespace -F "$msg" "$REL_TAG" "$tip" ||
		die "the tag $REL_TAG could not be created; $REL_AGAIN"
	say "tag $REL_TAG created on $REL_RELEASE (local: git publicar pushes it)"
}

# version_push: ONE atomic push of the version release: '<v>/RELEASE', the copies of the branches
# set aside, the deletion of the OT RELEASEs, of the integrated branches, of the old names and of
# '<v>/ORIGINAL'. Nothing when REL_PUSH is 0 or there is no origin. The tag is not pushed.
# Arguments: none; reads REL_RELEASE REL_TOP REL_ARCHIVE REL_DELETE_REMOTE. Returns: 0; exits
# through die when the push is rejected (nothing changed on origin; git release resumes).
version_push() {
	local refs=() leases=() entry b new name
	[ "$REL_PUSH" = 1 ] && has_origin || return 0
	refs=("refs/heads/$REL_RELEASE:refs/heads/$REL_RELEASE")
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new _ <<<"$entry"
		exists_ref "refs/remotes/origin/$b" || continue
		name="$(aside_existing "$b" || echo "$new")"
		exists_ref "refs/remotes/origin/$name" || refs+=("refs/remotes/origin/$b:refs/heads/$name")
	done
	for b in ${REL_DELETE_REMOTE[@]+"${REL_DELETE_REMOTE[@]}"} "$REL_TOP"; do
		# why: every deletion is under a lease on the tip we saw, so a push by someone else changes nothing
		if exists_ref "refs/remotes/origin/$b"; then
			refs+=(":refs/heads/$b")
			leases+=("--force-with-lease=refs/heads/$b:$(git rev-parse "refs/remotes/origin/$b")")
		fi
	done
	git push -q --atomic -u ${leases[@]+"${leases[@]}"} origin "${refs[@]}" ||
		die "the push of $REL_RELEASE was rejected; nothing changed on origin. Fix it and run git release --version $REL_VERSION again (it resumes)"
	say "pushed $REL_RELEASE (one atomic push; tag $REL_TAG stays local until git publicar)"
}

# version_release_report: the checks and the plan of the version release (preview and before
# running). Arguments: none; reads the REL_* variables. Returns: 0.
version_release_report() {
	local i=1
	rel_print_report "$REL_TOP is consistent (local/origin) and contains $QS_BR_MAINLINE" ""
	[ "$REL_RESUME" = 1 ] && echo "[ok] a version release of $REL_VERSION is in progress: git release resumes it (done: $(version_cfg ots | sed 's/^ *//'))"
	echo
	echo "## Plan"
	echo
	echo "$i. $REL_RELEASE at $REL_TOP; each OT RELEASE squashed into it as one commit, oldest first (CHANGELOG.md kept):${REL_VOTS[*]+ ${REL_VOTS[*]}}"
	i=$((i + 1))
	echo "$i. up to three commits: $(version_subject "$REL_VERSION"), docs(changelog): $REL_VERSION (union of the OT sections), docs(readme): version $REL_VERSION"
	i=$((i + 1))
	echo "$i. annotated tag $REL_TAG on the $REL_RELEASE tip (local until git publicar)"
	i=$((i + 1))
	echo "$i. $([ "$REL_PUSH" = 1 ] && has_origin && echo "one atomic push: $REL_RELEASE, ${#REL_ARCHIVE[@]} set aside, ${#REL_DELETE_REMOTE[@]} + $REL_TOP deleted on origin; then ")delete ${#REL_DELETE_LOCAL[@]} local branch(es), $REL_TOP last"
	i=$((i + 1))
	echo "$i. you: review $QS_BR_CHANGELOG on $REL_RELEASE; then git publicar"
	return 0
}

# version_changelog_preview: git changelog for a version (flow = squash): the OTs, the CHANGELOG.md
# entry the release would write, the checks and the plan. Changes nothing.
# Arguments: none; reads REL_VERSION REL_TAG. Returns: 0 when releasable; 1 when a check fails.
version_changelog_preview() {
	local o
	fetch_origin
	version_release_analyse
	echo "# Version release $REL_VERSION"
	echo
	for o in ${REL_VOTS[@]+"${REL_VOTS[@]}"}; do echo "- OT $o: $REL_VERSION/$o/$QS_BR_RELEASE_LEAF"; done
	for o in ${REL_MISSING[@]+"${REL_MISSING[@]}"}; do echo "- OT $o"; done
	echo
	local heading=""
	[ "${#REL_ERRORS[@]}" -eq 0 ] && heading="## $QS_BR_CHANGELOG entry (union of the OT sections)"
	rel_changelog_preview "$heading" version_union_notes version_release_report "git release --version $REL_VERSION"
}

# version_release_run: carry out the analysed version release: progress recorded, RELEASE created
# (or resumed), the OTs rebased, the release commits (skipped once the tag exists: the OT RELEASEs
# may be gone then), the tag, the branches set aside locally, the atomic push, the local
# deletions with '<v>/ORIGINAL' last, the progress forgotten.
# Arguments: none; reads the REL_* variables. Returns: 0; exits through die on a conflict or a
# rejected step (git release resumes).
version_release_run() {
	local o push="$REL_PUSH"
	git config "qs.release.$REL_VERSION.tag" "$REL_TAG"
	[ -n "$(version_cfg plan)" ] || version_cfg plan "${REL_VOTS[*]}"
	if ! exists_ref "refs/heads/$REL_RELEASE"; then
		git branch -q --no-track "$REL_RELEASE" "$(best_ref "$REL_RELEASE" || echo "$REL_TIP")"
	fi
	for o in "${REL_VOTS[@]}"; do version_rebase_ot "$o"; done
	git checkout -q "$REL_RELEASE"
	if ! exists_ref "refs/tags/$REL_TAG"; then
		REL_UNION=1
		release_commits
		REL_UNION=0
	fi
	version_tag_create
	REL_PUSH=0 # why: the copies on origin go in the atomic push below
	release_set_aside
	REL_PUSH="$push"
	version_push
	[ "${#REL_DELETE_LOCAL[@]}" -eq 0 ] || git branch -q -D "${REL_DELETE_LOCAL[@]}"
	! exists_ref "refs/heads/$REL_TOP" || git branch -q -D "$REL_TOP"
	# why: the tag name stays for git publicar (it reads qs.release.<v>.tag and clears it)
	version_progress_clear
	say "$REL_VERSION prepared on $REL_RELEASE: ${#REL_VOTS[@]} OT(s), $((${#REL_DELETE_LOCAL[@]} + 1)) branch(es) deleted, ${#REL_ARCHIVE[@]} set aside"
}

# version_release: git release of a version with branches.flow = squash (ACs V1-V6): checks,
# preview, confirmation, then version_release_run.
# Arguments: none; reads REL_VERSION REL_TAG REL_PUSH. Returns: 0; exits through die when a check
# fails, a rebase is stopped, or the human cancels (nothing changed).
version_release() {
	local o
	! rebase_in_progress || die "a rebase is stopped: finish it (git rebase --continue) or give it up (git rebase --abort), then run git release --version $REL_VERSION again"
	[ -z "$(git config --get "qs.release.$REL_VERSION.current" 2>/dev/null)" ] || [ -z "$(git diff --name-only --diff-filter=U)" ] ||
		die "the squash of an OT into $REL_VERSION/$QS_BR_RELEASE_LEAF still has conflicts. Solve them: edit the files, git add them, git commit (the message is ready); then run git release --version $REL_VERSION again. To start the OT again: git reset --hard $REL_VERSION/$QS_BR_RELEASE_LEAF"
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	if ! exists_branch "$REL_VERSION/$QS_BR_LEAF" && exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF"; then
		version_progress_clear
		say "$REL_VERSION/$QS_BR_RELEASE_LEAF is already prepared. Review $QS_BR_CHANGELOG there, then: git publicar --version $REL_VERSION"
		return 0
	fi
	version_forget_stale
	version_release_analyse
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		version_release_report >&2
		die "nothing was changed"
	fi
	echo "# Version release $REL_VERSION"
	echo
	for o in "${REL_VOTS[@]}"; do echo "- OT $o: $REL_VERSION/$o/$QS_BR_RELEASE_LEAF"; done
	echo
	version_release_report
	echo
	confirm "Prepare $REL_VERSION on $REL_RELEASE?" || die "cancelled; nothing was changed"
	version_release_run
	echo
	echo "Review now (you are on $REL_RELEASE):"
	echo "  git log --oneline $QS_BR_MAINLINE..$REL_RELEASE   # the OT commits and the release commits"
	echo "  \$EDITOR $QS_BR_CHANGELOG               # wording; commit it, then move the local tag: git tag -f -a $REL_TAG"
	echo "When it is right:"
	echo "  git publicar                          # $REL_RELEASE onto $QS_BR_MAINLINE, tag $REL_TAG pushed"
	return 0
}
