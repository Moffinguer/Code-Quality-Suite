#!/usr/bin/env bash
# special-integra.sh - integration order and refusals of the special branches (6.0.0 integra_order):
# what 'git integra' and 'git subir' refuse for each type, the order rules (REFACTOR last, FORMAT
# alone), the cleanup of the task's REVIEW/QUARANTINE/CHECKPOINT branches, and the checks the
# pre-merge-commit and pre-rebase hooks share. Source it after git-flow-lib.sh (it uses
# special_kind, special_prop, children_pending, best_ref, branch_node). Every function says "not
# special" (returns 1, prints nothing) with branches.flow = merge or for a disabled type.

# Whether the table says a type never goes up by 'git integra' from its own branch.
# Arguments: $1 type. Returns: 0 when its 'integrates' is never, apply or choose; 1 for squash.
si_type_never() {
	case "$(special_prop "$1" INTEGRATES)" in never | apply | choose) return 0 ;; esac
	return 1
}

# The type of a branch that must not be integrated or merged into <into>: its kind has
# integrates never/apply/choose and <into> is not inside the same special subtree (SPIKE/x goes
# into SPIKE/ORIGINAL normally, SPIKE/ORIGINAL into the node never).
# Arguments: $1 branch, $2 the branch it would go into. Returns: 0 and prints the type; 1 when the
# branch may go there.
si_never_type() {
	local t into
	t="$(special_kind "$1")"
	[ -n "$t" ] || return 1
	si_type_never "$t" || return 1
	into="$(special_kind "$2")"
	[ "$into" = "$t" ] && return 1
	printf '%s' "$t"
}

# The refusal text of git integra for a branch of a type that does not go up.
# Arguments: $1 branch, $2 type. Returns: 0; prints the sentence (ATTEMPT points to git elegir).
si_never_message() {
	local b="$1" t="$2" task
	case "$t" in
	ATTEMPT)
		task="${b%/*}"
		[ "${task##*/}" != "$QS_BR_LEAF" ] || task="${task%/*}"
		echo "'$b' is an ATTEMPT branch: it is never integrated, the human picks one: git elegir ${task##*/}"
		;;
	SPIKE) echo "'$b' is a SPIKE branch: it never goes outside its SPIKE subtree; take commits out with 'git spike --llevar'" ;;
	REVIEW) echo "'$b' is a REVIEW branch: it is never integrated; the author applies it with 'git revision --aplicar'" ;;
	QUARANTINE) echo "'$b' is a QUARANTINE branch: it is never integrated; take commits out with 'git aceptar'" ;;
	CHECKPOINT) echo "'$b' is a CHECKPOINT branch: a local save point, it is never integrated (git checkpoint --volver)" ;;
	*) echo "'$b' is a $t branch: it is never integrated (integrates: $(special_prop "$t" INTEGRATES))" ;;
	esac
}

# git integra: refuse a special branch that does not go up. Arguments: $1 branch, $2 its parent.
# Returns: 0 when it may be integrated; 1 with the reason on stderr when refused.
si_integra_refuse() {
	local t
	t="$(si_never_type "$1" "$2")" || return 0
	si_never_message "$1" "$t" >&2
	return 1
}

# The siblings of a branch that are not integrated yet and count for the order rules: children of
# its ORIGINAL that the table integrates by squash (SPIKE, REVIEW... are never integrated, so
# they never block anything).
# Arguments: $1 branch, $2 its ORIGINAL. Returns: 0; prints them space separated (maybe none).
si_pending_siblings() {
	local c out="" k
	for c in $(children_pending "$2"); do
		[ "$c" != "$1" ] || continue
		k="$(special_kind "$c")"
		if [ -n "$k" ] && si_type_never "$k"; then continue; fi
		out="$out $c"
	done
	printf '%s' "${out# }"
}

# git integra: the order of the types (REFACTOR last of its node, FORMAT alone, FORMAT never
# moved). Arguments: $1 branch, $2 its parent ORIGINAL. Returns: 0 when the order allows it; 1
# with the reason (the pending siblings are listed) on stderr otherwise.
si_integra_order() {
	local b="$1" parent="$2" t pend ptip
	t="$(special_kind "$b")"
	[ -n "$t" ] || return 0
	case "$(special_prop "$t" ORDER)" in last | alone) ;; *) return 0 ;; esac
	[ "$(special_prop "$t" AT)" = node ] || return 0
	pend="$(si_pending_siblings "$b" "$parent")"
	if [ -n "$pend" ]; then
		echo "'$b' ($t) goes in last: integrate these first: $pend" >&2
		return 1
	fi
	if [ "$(special_prop "$t" REBASE)" = 0 ]; then
		# why: a branch that is never rebased was made on the ORIGINAL tip of its time
		ptip="$(best_ref "$parent" || true)"
		if [ -n "$ptip" ] && ! git merge-base --is-ancestor "$ptip" "$b"; then
			echo "'$parent' moved since '$b' was made, and a $t branch is never rebased: run git formatear to regenerate it" >&2
			return 1
		fi
	fi
	return 0
}

# git subir: what a special branch does instead of the plain sync. Arguments: $1 branch.
# Returns: 0 when the branch syncs normally; 1 when subir must stop without error (CHECKPOINT:
# local only; the note is printed on stdout); 2 when refused (FORMAT; the reason is on stderr).
si_subir_check() {
	local t
	t="$(special_kind "$1")"
	case "$t" in
	CHECKPOINT)
		echo "[rama] '$1' is a CHECKPOINT: a local save point, it is never pushed or synced; nothing to do."
		return 1
		;;
	esac
	if [ -n "$t" ] && [ "$(special_prop "$t" REBASE)" = 0 ]; then
		echo "'$1' is a $t branch: it is never rebased or synced, $(special_command "$t") regenerates it" >&2
		return 2
	fi
	return 0
}

# The REVIEW, QUARANTINE and CHECKPOINT branches of a task: '<parent>/<TYPE>-<task>', local or on
# origin. Arguments: $1 the task branch ('<node>/<task>' or '<node>/<task>/ORIGINAL').
# Returns: 0; prints one branch name per line (maybe none).
si_task_extras() {
	local node dir task t
	node="$(branch_node "$1")"
	dir="${node%/*}"
	task="${node##*/}"
	[ "$dir" != "$node" ] || return 0
	for t in REVIEW QUARANTINE CHECKPOINT; do
		special_enabled "$t" || continue
		[ "$(special_kind "$dir/$t-$task")" = "$t" ] || continue
		git show-ref --verify -q "refs/heads/$dir/$t-$task" ||
			git show-ref --verify -q "refs/remotes/origin/$dir/$t-$task" || continue
		printf '%s\n' "$dir/$t-$task"
	done
}

# The branch refs to compare against when a merge or a rebase names a branch: a name as given
# ('origin/x' too) without refs/heads/ or the origin prefix.
# Arguments: $1 a branch name or ref. Returns: 0; prints the plain branch name.
si_plain_name() {
	local n="$1"
	n="${n#refs/heads/}"
	n="${n#refs/remotes/origin/}"
	n="${n#origin/}"
	printf '%s' "$n"
}

# pre-merge-commit: whether a merge into an ORIGINAL comes only from branches that never go up.
# A merge head that several branches point at (a SPIKE made at the ORIGINAL tip) is allowed when
# any of them is an ordinary branch.
# Arguments: $1 target branch, $2 newline-separated source branch names. Returns: 0 and prints the
# refusal when the merge must be refused; 1 when it is allowed or not about special branches.
si_merge_refusal() {
	local target="$1" s first="" t
	is_parent_branch "$target" || return 1
	while IFS= read -r s; do
		[ -n "$s" ] || continue
		t="$(si_never_type "$s" "$target")" || return 1
		[ -n "$first" ] || first="$s:$t"
	done <<<"$2"
	[ -n "$first" ] || return 1
	echo "[pre-merge-commit] '${first%%:*}' (${first##*:}) is never merged into '$target': $(si_never_message "${first%%:*}" "${first##*:}")"
}

# pre-rebase: refuse rebasing a branch that is never rebased (FORMAT) and rebasing anything onto a
# branch of a type that others must not build on (CHECKPOINT, QUARANTINE, REVIEW).
# Arguments: $1 the branch being rebased, $2 the upstream as git gives it. Returns: 0 and prints the
# refusal when the rebase must be refused; 1 when it is allowed.
si_rebase_refusal() {
	local b="$1" t u
	t="$(special_kind "$b")"
	if [ -n "$t" ] && [ "$(special_prop "$t" REBASE)" = 0 ]; then
		echo "[pre-rebase] '$b' is a $t branch: it is never rebased ($(special_command "$t") regenerates it)."
		return 0
	fi
	u="$(si_plain_name "$2")"
	case "$(special_kind "$u")" in
	CHECKPOINT | QUARANTINE | REVIEW)
		echo "[pre-rebase] nothing is rebased onto '$u' ($(special_kind "$u")): that branch is not a base for others."
		return 0
		;;
	esac
	return 1
}

# After a task is integrated: delete its REVIEW-<task>, QUARANTINE-<task> and CHECKPOINT-<task>
# branches, locally and on origin. A deleted branch prints its tip so it can be restored (git branch
# <name> <sha>); a kept branch prints only "kept". Asks per branch unless --yes. Needs say and
# confirm of git-rama.sh.
# Arguments: $1 the integrated task branch. Returns: 0; a branch that cannot be deleted is
# reported and kept.
si_drop_task_extras() {
	local x tip deleted
	for x in $(si_task_extras "$1"); do
		tip="$(git rev-parse -q --verify "refs/heads/$x" || git rev-parse -q --verify "refs/remotes/origin/$x")"
		if ! confirm "delete '$x' (task integrated), locally and on origin?" 2>/dev/null; then
			say "kept '$x'"
			continue
		fi
		# why: the restore line is printed only when something was really deleted
		deleted=0
		if git show-ref --verify -q "refs/heads/$x"; then
			if git branch -q -D "$x"; then
				deleted=1
			else
				say "could not delete '$x' locally (checked out in another worktree?)"
			fi
		fi
		if git show-ref --verify -q "refs/remotes/origin/$x"; then
			if git push -q origin --delete "$x"; then
				deleted=1
			else
				say "could not delete '$x' on origin"
			fi
		fi
		if [ "$deleted" = 1 ]; then
			say "'$x' was at $tip (restore: git branch $x $tip)"
		fi
	done
	return 0
}
