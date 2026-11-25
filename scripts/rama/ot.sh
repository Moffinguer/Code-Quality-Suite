#!/usr/bin/env bash
# rama/ot.sh - the OT release (git release inside a '<v>/<ot>' tree) (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

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

# release_forget_remote <branch>: drop a branch from REL_DELETE_REMOTE (its origin ref is already
# renamed, or must stay because the rename lost its lease).
# Arguments: $1 branch. Returns: 0.
release_forget_remote() {
	local x keep=()
	for x in ${REL_DELETE_REMOTE[@]+"${REL_DELETE_REMOTE[@]}"}; do [ "$x" = "$1" ] || keep+=("$x"); done
	REL_DELETE_REMOTE=(${keep[@]+"${keep[@]}"})
}

# release_delete_remote <branch>...: delete branches on origin, each under a lease on the tip the
# last fetch saw, so a branch someone else pushed to since is kept.
# Arguments: $@ branch names. Returns: 0; a failed push ends the script (set -e) as before.
release_delete_remote() {
	local x refs=() leases=()
	for x in "$@"; do
		exists_ref "refs/remotes/origin/$x" || continue
		refs+=(":refs/heads/$x")
		leases+=("--force-with-lease=refs/heads/$x:$(git rev-parse "refs/remotes/origin/$x")")
	done
	[ "${#refs[@]}" -eq 0 ] || git push -q "${leases[@]}" origin "${refs[@]}"
}

# release_set_aside: set every REL_ARCHIVE branch aside under its 'unmerged/...' name: renamed
# locally (or a local copy of a branch only on origin) and renamed on origin, in one atomic push
# under a lease, when REL_PUSH is 1 and there is an origin; one warning per branch on stderr.
# Arguments: none; reads REL_ARCHIVE ("<branch><TAB><new name><TAB><ORIGINAL><TAB><commits>").
# Returns: 0; a failed git command ends the script (set -e).
release_set_aside() {
	local entry b new p n done_as aside_sha rc
	for entry in ${REL_ARCHIVE[@]+"${REL_ARCHIVE[@]}"}; do
		IFS=$'\t' read -r b new p n <<<"$entry"
		if done_as="$(aside_existing "$b")"; then
			# a failed earlier run already set it aside: do not copy it again
			if [ "$REL_PUSH" = 1 ] && has_origin && ! exists_ref "refs/remotes/origin/$done_as"; then
				git push -q origin "refs/heads/$done_as:refs/heads/$done_as"
			fi
			continue
		fi
		aside_sha="$(git rev-parse -q --verify "refs/remotes/origin/$b" || true)"
		if exists_ref "refs/heads/$b"; then
			git branch -m "$b" "$new"
		else git branch -q --no-track "$new" "origin/$b"; fi # remote only: keep a local copy too
		if [ "$REL_PUSH" = 1 ] && has_origin && exists_ref "refs/remotes/origin/$b"; then
			# why: the rename on origin is one atomic push under a lease on the old tip; a lost lease
			# leaves origin as it is and the old name must not be deleted there later
			rc=0
			qs_publish_rename "$b" "$new" "$aside_sha" || rc=$?
			[ "$rc" != 1 ] || die "origin refused the rename of '$b' to '$new'; fix it and run git release again (it resumes)"
			[ "$rc" = 0 ] || echo "[rama] WARN: origin was not changed for '$b' ($new is local only). Ask the human before touching origin/$b (someone pushed to it)" >&2
			release_forget_remote "$b"
		elif [ "$REL_PUSH" = 1 ]; then
			qs_publish_new "$new" # why: a branch that never reached origin is published under its new name
		fi
		echo "[rama] WARN: $b had $n commit(s) not in $p: set aside as $new" >&2
	done
	return 0
}

# --- OT release (flow = squash): '<v>/<ot>/ORIGINAL' -> '<v>/<ot>/RELEASE' ---------------------
# git release inside '<v>/<ot>/...' (or --ot <v>/<ot>): RELEASE at the OT ORIGINAL tip plus one
# docs(changelog) commit with the OT lines of the '## <v>' section, the hidden ref (refs/ot/<v>/<ot>, never a tag)
# branches.ot_ref on the OT ORIGINAL tip (keeps the cited hashes reachable), one push of RELEASE
# and the ref, then the OT subtree deleted (the OT ORIGINAL last: while it exists the release is
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

# render_ot_ref <v>/<ot>: the ref of an OT release from branches.ot_ref ({version}, {ot}, {date}).
# Arguments: $1 '<v>/<ot>'. Returns: 0; prints the ref (nothing when ot_ref is '').
render_ot_ref() {
	local t="$QS_BR_OT_REF"
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
		[ -n "$o" ] && ! reserved_leaf_segment "$o" && [ -z "$(special_segment_type "$o")" ] && printf '%s\n' "$o"
	done < <(all_branches | awk -F/ -v v="$1" '$1 == v && NF >= 3 { print $2 }' | LC_ALL=C sort -u)
	return 0
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
		[ -n "$s" ] && qs_ref_exists "$s^{commit}" && excl+=("^$s")
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
	squashed_in_chain "$(best_ref "$b" || true)" "$(best_ref "$p" || true)" && return 0
	bt="$(branch_tip "$b")"
	pt="$(branch_tip "$p")"
	tree="$(git merge-tree --write-tree "$pt" "$bt" 2>/dev/null)" || return 1
	[ "$(head -n1 <<<"$tree")" = "$(git rev-parse "$pt^{tree}")" ]
}

# release_special_leftover <branch>: one policy for the special leftovers of an OT release: a branch
# whose special type has on_release = delete (SPIKE, ATTEMPT, REVIEW, QUARANTINE, CHECKPOINT) is
# deleted with the tree, never set aside (a CHECKPOINT must never reach origin: push = never). It
# is recorded in REL_SPECIAL ("<branch><TAB><type><TAB><tip sha>") and queued for deletion, on
# origin too (under a lease) when it was published.
# Arguments: $1 branch. Returns: 0 when it is such a leftover (recorded); 1 otherwise.
release_special_leftover() {
	local b="$1" kind ref
	kind="$(special_kind "$b")"
	[ -n "$kind" ] && [ "$(special_prop "$kind" ON_RELEASE)" = delete ] || return 1
	ref="$(best_ref "$b" || true)"
	[ -n "$ref" ] || return 1
	REL_SPECIAL+=("$b"$'\t'"$kind"$'\t'"$(git rev-parse "$ref")")
	exists_ref "refs/remotes/origin/$b" && REL_DELETE_REMOTE+=("$b")
	exists_ref "refs/heads/$b" && REL_DELETE_LOCAL+=("$b")
	return 0
}

# release_special_say: one line per special leftover deleted by the OT release: its tip and the
# command that restores it. Arguments: none; reads REL_SPECIAL. Returns: 0.
release_special_say() {
	local entry b kind sha
	for entry in ${REL_SPECIAL[@]+"${REL_SPECIAL[@]}"}; do
		IFS=$'\t' read -r b kind sha <<<"$entry"
		say "deleted $kind branch $b, was at $sha: git branch $b $sha"
	done
	return 0
}

# ot_release_analyse: analyse the OT REL_OT for its release; fills the REL_* variables of
# release_analyse plus REL_VTOP (the version ORIGINAL), REL_OT_REF and REL_DONE, prints only the
# TESTING warnings. Errors (REL_ERRORS): no OT ORIGINAL (and no RELEASE), local and origin
# diverged, the version ORIGINAL not contained, no own non-merge commit, the ref on another
# commit, a RELEASE that does not contain the OT ORIGINAL tip (reopening a released OT is not
# supported), a branch of the OT checked out in another worktree. REL_DONE=1 when only the
# RELEASE is left (released); REL_RESUME=1 when RELEASE already contains the OT ORIGINAL tip.
# The delete lists leave out REL_TOP, which ot_release_run deletes last.
# Arguments: none. Returns: 0.
ot_release_analyse() {
	local v="${REL_OT%%/*}" b p tb tp n rt vt
	REL_TOP="$REL_OT/$QS_BR_LEAF" REL_RELEASE="$REL_OT/$QS_BR_RELEASE_LEAF" REL_VTOP="$v/$QS_BR_LEAF"
	REL_ERRORS=() REL_OK=() REL_ARCHIVE=() REL_DELETE_LOCAL=() REL_DELETE_REMOTE=() REL_PLANNED=$'\n' REL_SPECIAL=()
	REL_TIP="" REL_BASE="" REL_CL_BASE="" REL_RESUME=0 REL_DONE=0
	REL_OT_REF="$(render_ot_ref "$REL_OT")"
	if [ -n "$REL_OT_REF" ] && { ! git check-ref-format "$REL_OT_REF" || [ "${REL_OT_REF#refs/ot/}" = "$REL_OT_REF" ]; }; then
		REL_ERRORS+=("branches.ot_ref gives '$REL_OT_REF', not a valid ref name under refs/ot/")
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
	if [ -n "$REL_OT_REF" ] && exists_ref "$REL_OT_REF" && [ "$REL_TIP" != diverged ] &&
		[ "$(git rev-parse "$REL_OT_REF^{commit}")" != "$REL_TIP" ]; then
		REL_ERRORS+=("ref '$REL_OT_REF' already exists on another commit (branches.ot_ref); move or delete it first")
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
		if release_special_leftover "$b"; then continue; fi
		tb="$(branch_tip "$b")"
		p="$(nearest_original "$b")"
		tp="$(branch_tip "$p")"
		if [ "$tb" = diverged ] || [ "$tp" = diverged ]; then
			REL_ERRORS+=("$([ "$tb" = diverged ] && echo "$b" || echo "$p"): local and origin diverged; run git subir on it first")
			continue
		fi
		if is_testing_branch "$b"; then
			if [ "$REL_TIP" != diverged ] && ot_testing_clean "$b"; then
				REL_OK+=("$b"$'\t'"$p (TESTING sandbox, nothing left to distribute)")
				continue
			fi
		elif ot_branch_in "$b" "$p"; then
			REL_OK+=("$b"$'\t'"$p")
			continue
		fi
		n="$(git rev-list --count --no-merges "$tp..$tb")"
		rel_archive_add "$b" "$p" "$n" || continue
	done < <(all_branches | awk -v p="$REL_OT/" 'index($0, p) == 1')
	rel_check_branches "$REL_OT"
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
# die when the engine cannot write the file or a hook rejects the commit; the changelog file is then
# restored (removed when new) so the rerun finds a clean tree.
ot_changelog_commit() {
	[ -n "$QS_BR_CHANGELOG" ] || return 0
	if [ -n "$(git rev-list -n1 "$REL_TIP..HEAD")" ]; then
		say "$REL_RELEASE already has its changelog commit: resumed"
		return 0
	fi
	if ! { ot_release_notes --write >/dev/null 2>&1 && ot_changelog_try_commit; }; then
		# why: a dirty changelog would make the rerun die in require_clean
		git reset -q -- "$QS_BR_CHANGELOG" 2>/dev/null || true
		if git cat-file -e "HEAD:$QS_BR_CHANGELOG" 2>/dev/null; then
			git checkout -q -- "$QS_BR_CHANGELOG" 2>/dev/null || true
		else rm -f -- "$QS_BR_CHANGELOG"; fi # why: a file the engine created has nothing to restore
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

# ot_ref_create: the hidden ref REL_OT_REF on the OT ORIGINAL tip (nothing when branches.ot_ref
# is '' or the ref is already there, which the analysis checked).
# Arguments: none. Returns: 0.
ot_ref_create() {
	[ -n "$REL_OT_REF" ] || return 0
	exists_ref "$REL_OT_REF" && return 0
	git update-ref "$REL_OT_REF" "$REL_TIP"
	say "ref $REL_OT_REF created on $REL_TOP ($(git rev-parse --short "$REL_TIP"))"
}

# ot_release_report: the checks and the plan of the OT release (preview and before running).
# Arguments: none; reads the REL_* variables. Returns: 0.
ot_release_report() {
	local entry b p new i=1
	rel_print_report "$REL_TOP is consistent (local/origin), contains $REL_VTOP and has its own commits" "contained in "
	for entry in ${REL_SPECIAL[@]+"${REL_SPECIAL[@]}"}; do
		IFS=$'\t' read -r b p new <<<"$entry"
		echo "[ok] $b: $p branch, will be deleted (was at $new)"
	done
	[ "$REL_RESUME" = 1 ] && echo "[ok] $REL_RELEASE exists and contains $REL_TOP: git release resumes from there"
	echo
	echo "## Plan"
	echo
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo "$i. set aside ${#REL_ARCHIVE[@]} branch(es) as $QS_BR_ARCHIVE/... (local and origin)"
		i=$((i + 1))
	fi
	if [ "${#REL_SPECIAL[@]}" -gt 0 ]; then
		echo "$i. delete ${#REL_SPECIAL[@]} special branch(es) (on_release = delete), with the restore line of each"
		i=$((i + 1))
	fi
	echo "$i. $REL_TOP -> $REL_RELEASE with one commit \"$(ot_changelog_subject)\" ($QS_BR_CHANGELOG); $QS_BR_VERSION_FILE and the README badge untouched"
	i=$((i + 1))
	[ -n "$REL_OT_REF" ] && echo "$i. hidden ref $REL_OT_REF on $REL_TOP ($([ "$REL_TIP" = diverged ] && echo diverged || git rev-parse --short "$REL_TIP"))" && i=$((i + 1))
	echo "$i. push $REL_RELEASE${REL_OT_REF:+ and $REL_OT_REF}; delete the OT subtree: $((${#REL_DELETE_LOCAL[@]} + 1)) local branch(es)$(has_origin && [ "$REL_PUSH" = 1 ] && echo ", $((${#REL_DELETE_REMOTE[@]} + 1)) on origin at most") ($REL_TOP last)"
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
	[ "$REL_TAG_GIVEN" = 0 ] || die "the OT release takes no tag: its ref is branches.ot_ref ($(render_ot_ref "$REL_OT"))"
	fetch_origin
	ot_release_analyse
	if [ "$REL_DONE" = 1 ]; then
		say "$REL_OT is released on $REL_RELEASE: next, git release --version ${REL_OT%%/*} once every OT is released"
		return 0
	fi
	local heading=""
	if [ -n "$REL_CL_BASE" ]; then
		ot_release_changes
		echo
		heading="## $QS_BR_CHANGELOG section (OT ${REL_OT#*/})"
	fi
	rel_changelog_preview "$heading" ot_release_notes ot_release_report "git release --ot $REL_OT"
}

# ot_release_run: carry out the analysed OT release: RELEASE created (or resumed) and checked out,
# the changelog commit, the ref, ONE push of RELEASE and the ref, the never-integrated branches set
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
	ot_ref_create
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		refs=("$REL_RELEASE")
		[ -n "$REL_OT_REF" ] && refs+=("$REL_OT_REF:$REL_OT_REF")
		git push -q --atomic -u origin "${refs[@]}" ||
			die "push of $REL_RELEASE failed; the OT tree is untouched. Fix it and run git release again (it resumes)"
	fi
	release_set_aside
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		[ "${#REL_DELETE_REMOTE[@]}" -eq 0 ] || release_delete_remote "${REL_DELETE_REMOTE[@]}"
		release_delete_remote "$REL_TOP"
	fi
	[ "${#REL_DELETE_LOCAL[@]}" -eq 0 ] || git branch -q -D "${REL_DELETE_LOCAL[@]}"
	! exists_ref "refs/heads/$REL_TOP" || git branch -q -D "$REL_TOP"
	release_special_say
	say "OT $REL_OT released on $REL_RELEASE: $((${#REL_DELETE_LOCAL[@]} + 1)) branch(es) of the OT deleted, ${#REL_ARCHIVE[@]} set aside"
	return 0
}

# ot_release: git release for one OT (AC O1-O7): checks, preview, confirmation, then ot_release_run.
# Arguments: none; reads REL_OT REL_TAG_GIVEN REL_PUSH. Returns: 0; exits through die when a check
# fails or the human cancels (nothing changed).
ot_release() {
	[ "$REL_TAG_GIVEN" = 0 ] || die "the OT release takes no tag: its ref is branches.ot_ref ($(render_ot_ref "$REL_OT"))"
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

# --- version release (flow = squash): every '<v>/<ot>/RELEASE' -> '<v>/RELEASE' ----------------
# git release on '<v>/ORIGINAL', develop or with --version <v>: refused (nothing changed) while an
# OT of the version has no '<v>/<ot>/RELEASE' or still has other branches. Otherwise '<v>/RELEASE'
# starts at '<v>/ORIGINAL' and each OT RELEASE, oldest first, is rebased onto it (its changelog-only
# commits dropped) on a detached HEAD, so the OT RELEASE refs stay as they were until the end. Then
# the version commit, the CHANGELOG.md entry (union of the OT sections as found on each OT RELEASE
# tip, plus the direct commits of '<v>/ORIGINAL') and the README badge; the annotated tag
# branches.tag on the RELEASE tip, local until git publicar; ONE atomic push (RELEASE, branches set
# aside, deletions); the OT RELEASEs and '<v>/ORIGINAL' deleted, '<v>/ORIGINAL' last. Progress is
# kept in git config qs.release.<v>.plan / .ots / .current, so any failure is resumed by running
# git release again. The tag name (qs.release.<v>.tag) stays until git publicar; it and the progress
# are forgotten when '<v>/RELEASE' is gone (version_forget_stale) or by git release --reset.
