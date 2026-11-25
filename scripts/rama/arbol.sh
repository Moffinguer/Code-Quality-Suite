#!/usr/bin/env bash
# rama/arbol.sh - git arbol and git estructura (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

# arbol_testing_sources <testing branch>: print the sources recorded in the marker commit of a
# TESTING sandbox ('Sources:' block of its Testing-Create commit), comma separated.
# Arguments: $1 the '<level>/TESTING' branch. Returns: 0; prints nothing when there is no marker.
arbol_testing_sources() {
	local ref m
	ref="$(best_ref "$1" || true)"
	[ -n "$ref" ] || return 0
	m="$(git log --first-parent -n1 --format=%H --grep='^Testing-Create: ' "$ref" 2>/dev/null || true)"
	[ -n "$m" ] || return 0
	git log -n1 --format=%B "$m" |
		awk '/^Sources:$/ { on = 1; next } on && NF == 0 { exit } on { printf "%s%s", sep, $1; sep = ", " }'
}

# checked_out_anywhere <branch>: succeed when <branch> is checked out in any worktree, this one
# included. Arguments: $1 branch. Returns: 0 checked out, 1 otherwise.
checked_out_anywhere() {
	git worktree list --porcelain | grep -qxF "branch refs/heads/$1"
}

# limpiar_verdict <branch> <original>: decide whether git arbol --limpiar may delete a branch.
# EVERY existing copy must be integrated in the copy of the ORIGINAL on the same side: the local
# copy in the local ORIGINAL, the origin copy in origin/<original>. Diverged copies are kept.
# Sets LV_DESC (how it is integrated) and LV_WHY (why it is kept, empty when it is just pending
# and not worth a line). Arguments: $1 branch, $2 ORIGINAL name. Returns: 0 deletable, 1 kept.
limpiar_verdict() {
	local b="$1" p="$2" lb="refs/heads/$1" rb="refs/remotes/origin/$1"
	local lp="refs/heads/$2" rp="refs/remotes/origin/$2" ld="" rd="" rld=""
	LV_DESC="" LV_WHY=""
	if exists_ref "$lb"; then ld="$(copy_integrated "$lb" "$b" "$p" "$lp")" || ld=""; fi
	if exists_ref "$rb"; then
		rd="$(copy_integrated "$rb" "$b" "$p" "$rp")" || rd=""
		rld="$(copy_integrated "$rb" "$b" "$p" "$lp")" || rld=""
	fi
	if exists_ref "$lb" && exists_ref "$rb" &&
		! git merge-base --is-ancestor "$lb" "$rb" && ! git merge-base --is-ancestor "$rb" "$lb"; then
		[ -z "$ld$rd$rld" ] || LV_WHY="local and origin copies diverged"
		return 1
	fi
	if exists_ref "$lb" && [ -z "$ld" ]; then
		[ -z "$rd" ] || LV_WHY="the local copy is not integrated (the origin one is)"
		return 1
	fi
	if exists_ref "$rb" && [ -z "$rd" ]; then
		if [ -n "$rld" ]; then
			LV_WHY="$rld, but not in origin/$p: git push origin $p"
		elif [ -n "$ld" ]; then
			LV_WHY="the origin copy is not integrated (the local one is)"
		fi
		return 1
	fi
	LV_DESC="${ld:-$rd}"
	return 0
}

# arbol_limpiar <prefix>: git arbol --limpiar (branches.flow = squash). Lists the branches that
# git integra squashed into their ORIGINAL (a 'Refs:' trailer) or that are ancestors of it, and
# deletes them after a confirmation (--yes skips it), only when every copy is integrated (see
# limpiar_verdict). The origin copies go in one 'git push --atomic' with a lease on each expected
# sha; the local copies are deleted only after that succeeded. Never deleted: an ORIGINAL with
# children not integrated yet, a RELEASE, a TESTING sandbox, an 'unmerged/...' branch, a mainline
# branch, anything checked out in a worktree. Arguments: $1 version prefix (may be empty).
# Returns: 0; 1 when a deletion failed; exits through die with flow = merge.
arbol_limpiar() {
	local prefix="$1" b p pending where n failed=0 changed
	local -a gone=() descs=() delete_args=() lim_held=() lim_hdesc=() lim_rest=() lim_rdesc=()
	[ "${QS_BR_FLOW:-merge}" = squash ] || die "--limpiar needs branches.flow = squash (with merge the branches are ancestors: git branch -d)"
	fetch_origin
	while IFS= read -r b; do
		[ -z "$prefix" ] || case "$b" in "$prefix"/* | "$prefix") ;; *) continue ;; esac
		is_mainline "$b" && continue
		is_archived_branch "$b" && continue
		valid_branch_name "$b" >/dev/null 2>&1 || continue
		is_testing_branch "$b" && continue
		{ is_release_branch "$b" || is_ot_release_branch "$b"; } && continue
		p="$(parent_branch "$b")"
		[ -n "$p" ] || continue
		if ! exists_ref "refs/heads/$p" && ! exists_ref "refs/remotes/origin/$p"; then
			# its parent was squashed and deleted: the nearest ORIGINAL above holds the work
			p="$(REL_TOP="" nearest_original "$b")"
			[ -n "$p" ] || continue
			exists_ref "refs/heads/$p" || exists_ref "refs/remotes/origin/$p" || continue
		fi
		if ! limpiar_verdict "$b" "$p"; then
			[ -z "$LV_WHY" ] || say "kept '$b': $LV_WHY"
			continue
		fi
		if checked_out_anywhere "$b"; then
			say "kept '$b': $LV_DESC, but checked out in a worktree"
			continue
		fi
		if is_parent_branch "$b"; then
			# why: its children may be in this run's delete set, which is not complete yet
			lim_held+=("$b")
			lim_hdesc+=("$LV_DESC")
			continue
		fi
		gone+=("$b")
		descs+=("$LV_DESC")
	done < <(
		{
			git for-each-ref --format='%(refname:short)' refs/heads/
			git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | { grep -v '^HEAD$' || true; }
		} | sort -u
	)
	# parent ORIGINALs: deletable when each child is integrated or in the delete set (repeat: a
	# parent that goes may free the parent above it)
	changed=1
	while [ "$changed" = 1 ] && [ "${#lim_held[@]}" -gt 0 ]; do
		changed=0
		lim_rest=() lim_rdesc=()
		for n in "${!lim_held[@]}"; do
			pending="$(children_pending "${lim_held[$n]}" ${gone[@]+"${gone[@]}"})"
			if [ -z "$pending" ]; then
				gone+=("${lim_held[$n]}")
				descs+=("${lim_hdesc[$n]}")
				changed=1
			else
				lim_rest+=("${lim_held[$n]}")
				lim_rdesc+=("${lim_hdesc[$n]}")
			fi
		done
		lim_held=(${lim_rest[@]+"${lim_rest[@]}"}) lim_hdesc=(${lim_rdesc[@]+"${lim_rdesc[@]}"})
	done
	for n in "${!lim_held[@]}"; do
		pending="$(children_pending "${lim_held[$n]}" ${gone[@]+"${gone[@]}"})"
		say "kept '${lim_held[$n]}': ${lim_hdesc[$n]}, but children not integrated: $pending"
	done
	if [ "${#gone[@]}" = 0 ]; then
		say "nothing to clean: no integrated branch to delete"
		return 0
	fi
	for n in "${!gone[@]}"; do
		b="${gone[$n]}"
		where="origin only"
		exists_ref "refs/heads/$b" && where="local"
		exists_ref "refs/heads/$b" && exists_ref "refs/remotes/origin/$b" && where="local and origin"
		say "integrated: $b = ${descs[$n]} ($where)"
	done
	confirm "delete these ${#gone[@]} branch(es), locally and on origin?" 2>/dev/null || {
		say "nothing deleted"
		return 0
	}
	for b in "${gone[@]}"; do
		exists_ref "refs/remotes/origin/$b" || continue
		delete_args+=("--force-with-lease=refs/heads/$b:$(git rev-parse "refs/remotes/origin/$b")" ":refs/heads/$b")
	done
	if [ "${#delete_args[@]}" -gt 0 ]; then
		if ! git push -q --atomic origin "${delete_args[@]}"; then
			say "could not delete on origin (atomic push refused: a branch moved, or no permission); nothing was deleted"
			return 1
		fi
	fi
	for b in "${gone[@]}"; do
		if exists_ref "refs/heads/$b"; then
			if git branch -q -D "$b"; then say "deleted '$b'"; else
				say "could not delete '$b' locally"
				failed=1
			fi
		else
			say "deleted '$b' (origin)"
		fi
	done
	return "$failed"
}

# cmd_arbol [prefix] [--limpiar]: print the branch tree (parents '+', finals '-', pending commits,
# behind state). With branches.flow = squash it reads the 'Refs:'/'Squashed:' trailers like git
# integra (an integrated branch shows '= integrated as <sha>') and marks TESTING sandboxes (with
# their sources) and the OT and version RELEASE; flow = merge prints exactly what 4.x did.
# --limpiar deletes the integrated branches (arbol_limpiar). Returns: 0 (1 when a deletion failed); die on unknown options.
cmd_arbol() {
	local cur prefix="" a clean=0 squash=0
	for a in "$@"; do
		case "$a" in
		--limpiar) clean=1 ;;
		-*) die "unknown option '$a' (arbol: [prefix] [--limpiar] [--yes])" ;;
		*) prefix="$a" ;;
		esac
	done
	qs_policy_load
	[ "${QS_BR_FLOW:-merge}" != squash ] || squash=1
	cur="$(current_branch || true)"
	if [ -z "$prefix" ] && [ -n "$cur" ] && ! is_mainline "$cur"; then prefix="$(branch_version "$cur")"; fi
	if [ "$clean" = 1 ]; then
		arbol_limpiar "$prefix"
		return $?
	fi
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
			local ind="" p pref ref st="" i depth ahead behind sha plain=0
			if [ "$node" = "~" ]; then
				if is_archived_branch "$b"; then echo "~  $b   (set aside by git release)"; else echo "!  $b   (off-model)"; fi
				continue
			fi
			depth="$(awk -F/ '{print NF}' <<<"$node")"
			for ((i = 1; i < depth; i++)); do ind="$ind   "; done
			p="$(parent_branch "$b")"
			pref="$(best_ref "$p" || true)"
			ref="$(best_ref "$b" || true)"
			if [ "$squash" = 1 ]; then
				if is_testing_branch "$b"; then
					st=" [TESTING: sources $(arbol_testing_sources "$b")]"
					plain=1
				elif is_ot_release_branch "$b"; then
					st=" [OT RELEASE]"
					plain=1
				elif is_release_branch "$b"; then
					st=" [version RELEASE]"
					plain=1
				elif [ -n "$p" ] && exists_ref "refs/heads/$p" && sha="$(integrated_sha "$b" "$p")"; then
					st=" = integrated as $sha (git arbol --limpiar deletes it)"
					plain=1
				fi
			fi
			if [ "$plain" = 0 ] && [ -n "$pref" ] && [ -n "$ref" ]; then
				ahead="$(git rev-list --count "$pref..$ref")"
				behind="$(git rev-list --count "$ref..$pref")"
				if [ "$ahead" = 0 ]; then st=" (nothing pending for $p)"; else
					st=" (+$ahead pending"
					[ "$behind" = 0 ] && st="$st)" || st="$st, $behind behind $p)"
				fi
			fi
			exists_ref "refs/heads/$b" || st="$st (remote only)"
			# why: a branch only here (offline, refused push, publish off) is not shared yet
			if has_origin && exists_ref "refs/heads/$b" && ! exists_ref "refs/remotes/origin/$b"; then st="$st [local]"; fi
			printf '%s%s %s%s%s%s\n' "$ind" "$(is_parent_branch "$b" && echo '+' || echo '-')" "$b" \
				"$(special_marker "$b")" "$([ "$b" = "$cur" ] && echo '  <- you are here')" "$st"
		done
	special_arbol_warnings "$prefix"
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
    # add(node, par): awk helper. Records the path and its prefixes once, in order, and marks the
    # ancestors as parents; par marks the node itself. Arguments: node path; par. Errors: none.
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

# exists_branch NAME: tell whether NAME is a local branch or an origin branch.
# Arguments: $1 branch name. Returns: 0 when it exists, 1 otherwise. Errors: none; prints nothing.
exists_branch() { exists_ref "refs/heads/$1" || exists_ref "refs/remotes/origin/$1"; }
# has_branches_under NAME: tell whether a local or origin branch lies under the folder NAME/.
# Arguments: $1 folder name. Returns: 0 when one exists, 1 otherwise. Errors: none; prints nothing.
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

# cmd_estructura [-n|--dry-run] [--push] [--convertir] [FILE|-]...: create the branch tree read
# from the files or stdin (one branch per line, indented children; parsed by parse_structure).
# -n only shows the plan, --push pushes the new branches, --convertir turns plain branches into parents.
# Arguments: the options and the input files ('-' or none for stdin). Returns: 0 when done.
# Errors: dies on an unknown option, an empty input, a missing file or mainline; every name is
# validated first, so nothing is created when one is invalid.
cmd_estructura() {
	local dry=0 push=0 conv=0 files=() f a plan kind node b p base errs=0 why planned=$'\n' versions=""
	local topush=() created=() n_new=0 n_ok=0
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
		if why="$(special_migration_lock "${node%%/*}" "$b")"; then
			echo "  ! $b: $why" >&2
			errs=$((errs + 1))
			continue
		fi
		if why="$(special_node_refusal "$node")"; then
			echo "  ! $b: $why" >&2
			errs=$((errs + 1))
			continue
		fi
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
			created+=("$b")
		fi
		planned="$planned$b"$'\n'
		n_new=$((n_new + 1))
	done 3<"$plan"

	if [ "$dry" = 1 ]; then
		say "dry run: $n_new to create, $n_ok existing; nothing was changed"
		return 0
	fi
	say "$n_new created, $n_ok already existing (current branch unchanged: $(current_branch || echo detached))"
	# why: what this run created goes up in ONE push; --push is for the branches that already existed
	if [ "${#created[@]}" -gt 0 ]; then
		qs_publish_new "${created[@]}"
		if qs_publish_on; then
			local rest=() t
			for t in "${topush[@]}"; do case " ${created[*]} " in *" $t "*) ;; *) rest+=("$t") ;; esac done
			topush=(${rest[@]+"${rest[@]}"})
		fi
	fi
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
