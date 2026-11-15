#!/usr/bin/env bash
# git-flow-lib.sh - shared helpers for the branch model (sourced, not executed).
#
# Model: <version>/<ot>/<detail>/... separated by '/'.
#   6.22.6/ORIGINAL                      version branch (parent of its OTs)
#   6.22.6/188858/ORIGINAL               OT branch (parent)
#   6.22.6/188858/RF001/ORIGINAL         parent of RF001's branches
#   6.22.6/188858/RF001/login            final branch (sibling of RF001/ORIGINAL)
# why the ORIGINAL leaf: git stores refs as files and folders, so a branch cannot share its
# name with a folder of other branches ('a/b' and 'a/b/c' cannot coexist, locally or in
# remote-tracking refs). A branch that has children is '<folder>/ORIGINAL'; any other branch
# is final. Parent of '<F>/ORIGINAL' = '<dirname F>/ORIGINAL' (mainline at the top); parent of
# '<F>/<leaf>' = '<F>/ORIGINAL'. Siblings share <F>. Derived from the name: same for everyone.
# Policy (leaf name, level patterns, tag...) comes from .quality-rules.json -> "branches".

mainline_prod() { git show-ref --verify -q refs/heads/main && echo main || echo master; }
current_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null; }

# Set the built-in commit/branch policy defaults (overridden by .quality-rules.json).
# Arguments: none. Returns: 0.
# shellcheck disable=SC2034 # why: these QS_* variables are read by the scripts that source this file
qs_policy_defaults() {
	QS_COMMIT_CHARSET=ascii QS_COMMIT_TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
	QS_COMMIT_SUBJECT_MAX=50 QS_COMMIT_CONVENTIONAL=1 QS_COMMIT_FILES=block
	QS_BR_ENFORCE=block QS_BR_LEAF=ORIGINAL QS_BR_MAINLINE=develop QS_BR_PROTECTED='main master develop'
	QS_BR_SEGMENT='^[A-Za-z0-9][A-Za-z0-9_-]*$' QS_BR_LEAF_MERGE=merge QS_BR_REQUIRE_CHILDREN=1
	QS_BR_FLOW=squash QS_BR_OT_TAG='ot/{version}/{ot}' QS_BR_TESTING=TESTING
	QS_BR_TAG='{version}' QS_BR_TAG_LEVEL=1 QS_BR_LEVELS=2 QS_BR_ALLOW=0
	QS_BR_RELEASE_LEAF=RELEASE QS_BR_ARCHIVE=unmerged
	QS_BR_VERSION_FILE=VERSION QS_BR_CHANGELOG=CHANGELOG.md QS_BR_README=README.md QS_BR_POM=update
	QS_BR_TAG_URL='' QS_BR_COMMIT_URL=''
	# level 1: Semantic Versioning without build metadata (https://semver.org)
	QS_BR_LEVEL_1='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$'
	# level 2 (the OT): ASCII letters and digits, no '-' or '_'; numeric OTs match too
	QS_BR_LEVEL_2='^[A-Za-z0-9]+$'
}

# Load the commit/branch policy into QS_* variables. The engine writes <state>/policy.env on
# every run; when the rules file is newer (edited since), it is regenerated with the image.
qs_policy_load() {
	[ "${QS_POLICY_LOADED:-0}" = 1 ] && return 0
	qs_policy_defaults
	local gd root pol rules
	gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 0
	root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
	pol="$gd/quality-suite/policy.env"
	rules="${root:+$root/.quality-rules.json}"
	if [ -n "$rules" ] && [ -f "$rules" ] && { [ ! -f "$pol" ] || [ "$rules" -nt "$pol" ]; } &&
		[ -n "${QUALITY_SUITE_DIR:-}" ] && command -v docker >/dev/null 2>&1 && [ "${QS_POLICY_NO_DOCKER:-0}" != 1 ]; then
		# shellcheck disable=SC1091
		. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
		mkdir -p "$gd/quality-suite"
		: >"$gd/quality-suite/policy.list"
		if qs_engine_query policy "$gd/quality-suite/policy.list" >"$pol.tmp" 2>/dev/null && [ -s "$pol.tmp" ]; then
			mv "$pol.tmp" "$pol"
		else rm -f "$pol.tmp"; fi
	fi
	# shellcheck disable=SC1090
	[ -f "$pol" ] && . "$pol"
	QS_POLICY_LOADED=1
}

_br_level_re() {
	local v="QS_BR_LEVEL_$1"
	printf '%s' "${!v:-$QS_BR_SEGMENT}"
}
is_mainline() {
	case " $QS_BR_PROTECTED $QS_BR_MAINLINE " in *" $1 "*) return 0 ;; esac
	return 1
}
is_parent_branch() { [ "${1##*/}" = "$QS_BR_LEAF" ] && [ "$1" != "$QS_BR_LEAF" ]; }
# '<version>/RELEASE': the version ORIGINAL during 'git release' (tagged, merged into develop, deleted)
is_release_branch() {
	case "$1" in */*/* | */) return 1 ;; */"$QS_BR_RELEASE_LEAF") ;; *) return 1 ;; esac
	printf '%s' "${1%%/*}" | grep -qE -- "$(_br_level_re 1)"
}
# Whether a branch is the RELEASE of one OT: '<version>/<ot>/RELEASE', exactly three segments, the
# version and the OT matching branches.levels (made by git release inside the OT, flow = squash).
# Arguments: $1 branch. Returns: 0 when it is one, 1 otherwise.
is_ot_release_branch() {
	local node
	case "$1" in */*/*/* | */) return 1 ;; */*/"$QS_BR_RELEASE_LEAF") ;; *) return 1 ;; esac
	node="${1%/*}"
	printf '%s' "${node%%/*}" | grep -qE -- "$(_br_level_re 1)" &&
		printf '%s' "${node#*/}" | grep -qE -- "$(_br_level_re 2)"
}

# Whether a segment is one of the reserved leaves (branches.parent_leaf, release_leaf and
# testing_leaf), ignoring case: on Windows 'release' and 'RELEASE' are the same ref file.
# Arguments: $1 segment. Returns: 0 when reserved, 1 otherwise.
reserved_leaf_segment() {
	local s l
	s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
	for l in "$QS_BR_LEAF" "$QS_BR_RELEASE_LEAF" "${QS_BR_TESTING:-TESTING}"; do
		[ -n "$l" ] && [ "$s" = "$(printf '%s' "$l" | tr '[:upper:]' '[:lower:]')" ] && return 0
	done
	return 1
}

# Check the reserved leaves of a branch name: the parent leaf only as the exact last segment, the
# TESTING leaf only as the exact last segment of '<F>/TESTING', no other segment equal to a
# reserved leaf in any case (the RELEASE branches are accepted earlier by their own checks). That
# broad refusal applies only with flow = squash; with flow = merge only the exact parent leaf is
# reserved, as in 4.x.
# Arguments: $1 branch. Returns: 0 when fine; 1 and prints the reason otherwise.
reserved_segments_ok() {
	local b="$1" n i=0 seg
	n="$(awk -F/ '{print NF}' <<<"$b")"
	while IFS= read -r seg; do
		i=$((i + 1))
		[ "$i" -eq "$n" ] && [ "$seg" = "$QS_BR_LEAF" ] && continue
		[ "$i" -eq "$n" ] && [ "$n" -ge 2 ] && [ "$seg" = "${QS_BR_TESTING:-TESTING}" ] && continue
		if [ "$seg" = "$QS_BR_LEAF" ]; then
			echo "'$QS_BR_LEAF' can only be the last segment"
			return 1
		fi
		if [ "${QS_BR_FLOW:-squash}" = squash ] && reserved_leaf_segment "$seg"; then
			echo "'$seg' is reserved ($QS_BR_LEAF, $QS_BR_RELEASE_LEAF and ${QS_BR_TESTING:-TESTING}, in any case)"
			return 1
		fi
	done < <(tr '/' '\n' <<<"$b")
	return 0
}

# 'unmerged/<name>' or 'unmerged-<stamp>/<name>' (prefix taken): a branch set aside by 'git release'
# because it was never integrated
is_archived_branch() {
	case "$1" in "$QS_BR_ARCHIVE"/?* | "$QS_BR_ARCHIVE"-*/?*) return 0 ;; esac
	return 1
}
# node path: '<F>' for '<F>/ORIGINAL', the branch itself for a final branch
branch_node() { if is_parent_branch "$1"; then printf '%s' "${1%/*}"; else printf '%s' "$1"; fi; }
branch_depth() {
	local n
	n="$(branch_node "$1")"
	awk -F/ '{print NF}' <<<"$n"
}
branch_version() { printf '%s' "${1%%/*}"; }
branch_ot() {
	local r="${1#*/}"
	r="${r%%/*}"
	[ "$r" = "$QS_BR_LEAF" ] || printf '%s' "$r"
}

# parent_branch <branch> -> parent per the model; empty for main/master/unknown.
parent_branch() {
	local b="$1" node up
	qs_policy_load
	case "$b" in main | master) return 0 ;; esac
	if [ "$b" = "$QS_BR_MAINLINE" ]; then
		mainline_prod
		return 0
	fi
	is_mainline "$b" && return 0
	# why: an OT RELEASE goes into the version RELEASE, which starts at the version ORIGINAL
	if is_ot_release_branch "$b"; then
		echo "${b%%/*}/$QS_BR_LEAF"
		return 0
	fi
	if is_release_branch "$b"; then
		echo "$QS_BR_MAINLINE"
		return 0
	fi
	is_archived_branch "$b" && return 0 # set aside: no parent
	is_testing_branch "$b" && return 0  # TESTING sandbox: no parent, never merged
	valid_branch_name "$b" >/dev/null 2>&1 || return 0
	node="$(branch_node "$b")"
	if is_parent_branch "$b"; then
		case "$node" in */*)
			up="${node%/*}"
			echo "$up/$QS_BR_LEAF"
			;;
		*) echo "$QS_BR_MAINLINE" ;; esac
	else
		echo "${node%/*}/$QS_BR_LEAF"
	fi
}

# valid_branch_name <branch>: 0 if it follows the model (prints the reason otherwise).
valid_branch_name() {
	local b="$1" i=0 seg rx n last
	qs_policy_load
	is_mainline "$b" && return 0
	{ is_release_branch "$b" || is_ot_release_branch "$b" || is_archived_branch "$b"; } && return 0
	for ((i = 1; i <= ${QS_BR_ALLOW:-0}; i++)); do
		rx="QS_BR_ALLOW_$i"
		printf '%s' "$b" | grep -qE -- "${!rx}" && return 0
	done
	if LC_ALL=C grep -q '[^ -~]' <<<"$b"; then
		echo "only ASCII characters are allowed"
		return 1
	fi
	reserved_segments_ok "$b" || return 1
	case "$b" in
	*/*) ;;
	*)
		if printf '%s' "$b" | grep -qE -- "$(_br_level_re 1)"; then
			echo "a branch is never only '<version>': use '$b/$QS_BR_LEAF' (git np $b) or '$b/<ot>'"
		else echo "expected <version>/<ot>/<detail>..., e.g. 6.22.6/188858/login (git np / git nr)"; fi
		return 1
		;;
	esac
	n="$(awk -F/ '{print NF}' <<<"$b")"
	last="${b##*/}"
	i=0
	while IFS= read -r seg; do
		i=$((i + 1))
		if [ "$i" -eq "$n" ] && [ "$seg" = "$QS_BR_LEAF" ]; then break; fi
		if [ "$i" -eq "$n" ] && [ "$n" -ge 2 ] && [ "$seg" = "${QS_BR_TESTING:-TESTING}" ]; then break; fi
		if [ "$seg" = "$QS_BR_LEAF" ]; then
			echo "'$QS_BR_LEAF' can only be the last segment"
			return 1
		fi
		rx="$(_br_level_re "$i")"
		printf '%s' "$seg" | grep -qE -- "$rx" || {
			echo "segment $i '$seg' does not match $rx"
			return 1
		}
	done < <(tr '/' '\n' <<<"$b")
	[ -n "$last" ] || {
		echo "empty last segment"
		return 1
	}
	return 0
}

# branches (local and remote-tracking, deduplicated) directly under the node of a parent branch
branch_children() {
	local p="$1" f
	f="$(branch_node "$p")"
	{
		git for-each-ref --format='%(refname:short)' "refs/heads/$f/"
		git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/$f/"
	} 2>/dev/null |
		awk -v f="$f/" -v leaf="$QS_BR_LEAF" -v me="$p" -v tst="${QS_BR_TESTING:-TESTING}" '
        index($0, f) == 1 { r = substr($0, length(f) + 1); n = split(r, a, "/");
          if ($0 != me && a[1] != tst && (n == 1 || (n == 2 && a[2] == leaf))) print $0 }' | sort -u
}

# branch ref to use as a base: origin/<b> when it exists and is ahead of (or equal to) the local one
best_ref() {
	local b="$1"
	if git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null 2>&1; then
		if ! git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1 ||
			git merge-base --is-ancestor "refs/heads/$b" "refs/remotes/origin/$b"; then
			echo "origin/$b"
			return 0
		fi
	fi
	git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1 && echo "$b"
}

# Render the release tag of a branch from the tag template (QS_BR_TAG).
# Arguments: $1 branch (<version>/<ot>/...). Returns: 0; prints the tag, no newline.
# Loads the policy first, so it also works when the library is sourced on its own.
render_tag() {
	local b="$1" t
	qs_policy_load
	t="$QS_BR_TAG"
	t="${t//\{version\}/$(branch_version "$b")}"
	t="${t//\{ot\}/$(branch_ot "$b")}"
	t="${t//\{date\}/$(date +%Y%m%d)}"
	printf '%s' "$t"
}

# Check that the working tree and the index have no uncommitted changes.
# Arguments: none. Returns: 0 when clean; 1 (with a message on stderr) when not.
require_clean() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "[git-flow] Working tree not clean; commit or stash first." >&2
		return 1
	fi
}

# configure_repo <suite_dir> - repo-LOCAL config + aliases (idempotent).
configure_repo() {
	local suite="$1" a
	git config pull.rebase true
	git config rebase.autoStash true
	git config branch.autoSetupRebase always
	git config push.default current
	git config merge.ff false
	git config rerere.enabled true
	git config rerere.autoupdate true
	git config fetch.prune true # why: deleted/renamed branches would block 'a/b' -> 'a/b/ORIGINAL'
	# why: git aliases (the team asked for plain git commands); short and long names
	for a in np:nueva-padre nueva-padre:nueva-padre nr:nueva-final nueva-final:nueva-final \
		convertir-padre:convertir-padre integra:integra subir:subir arbol:arbol \
		estructura:estructura es:estructura changelog:changelog release:release \
		publicar:publicar repo-files:repo-files ficheros-repo:repo-files \
		nueva-version:nueva-version nv:nueva-version combinar:combinar; do
		git config "alias.${a%%:*}" "!bash '$suite/scripts/git-rama.sh' ${a#*:}"
	done
	# why: `git commit --amend -m` looks like a normal commit to the hooks (no /proc on Windows);
	# QS_AMEND=1 tells prepare-commit-msg it is an amend
	git config alias.amend '!f() { QS_AMEND=1 git commit --amend "$@"; }; f'
	git config alias.limpiar-unmerged "!bash '$suite/scripts/git-unmerged.sh'"
	git config alias.encoding "!bash '$suite/scripts/qs-run.sh' --encoding"
	git config alias.testing "!bash '$suite/scripts/git-testing.sh'" # TESTING sandbox
	# why: every version tree writes its version into VERSION and pom.xml; a merge driver keeps
	# the branch's version (the released one on the mainline) instead of a conflict on every subir
	git config merge.qs-version.name "code-quality-suite: version files keep the branch version"
	git config merge.qs-version.driver "bash '$suite/scripts/merge-version.sh' %O %A %B %P"
	local attrs f
	attrs="$(git rev-parse --git-path info/attributes)"
	mkdir -p "$(dirname "$attrs")"
	touch "$attrs"
	for f in "/${QS_BR_VERSION_FILE:-VERSION}" pom.xml package.json; do
		grep -qxF "$f merge=qs-version" "$attrs" || printf '%s merge=qs-version\n' "$f" >>"$attrs"
	done
}

# --- flow squash: is a child integrated into its ORIGINAL? -----------------------------------
# why: a squash commit has one parent, so ancestry no longer proves a child is in; git integra
# records 'Refs: <child> -> <ORIGINAL>' and 'Squashed: <child> <full sha>' in the squash commit.

# branch_integrated <child> <original>: succeed when <child> is in <original>: its tip is an
# ancestor of <original>, or a commit of <original> has the line 'Refs: <child> -> <original>'
# and (when that commit also has 'Squashed: <child> <sha>') the child tip is contained in <sha>,
# i.e. the child did not move after its squash. A child that does not exist counts as in.
# Arguments: $1 child branch, $2 ORIGINAL branch name. Returns: 0 in, 1 pending.
branch_integrated() {
	local c="$1" p="$2" cref
	cref="$(best_ref "$c" || true)"
	[ -n "$cref" ] || return 0
	git merge-base --is-ancestor "$cref" "$p" 2>/dev/null && return 0
	squash_in "$cref" "$c" "$p" "$p"
}

# squash_in <tipref> <child> <original> <pref>: succeed when a commit of <pref> (a copy of the
# ORIGINAL: local or origin/...) has the line 'Refs: <child> -> <original>' and, when that commit
# also has 'Squashed: <child> <sha>', the tip of <tipref> is contained in <sha> (the child did not
# move after its squash). A 'Refs:' line without 'Squashed:' (hand-written squash) is taken as
# recorded. Arguments: $1 ref of the child copy, $2 child, $3 ORIGINAL name, $4 ref searched.
# Returns: 0 integrated, 1 not.
squash_in() {
	local tip bodies sha found=0 squashed=0
	tip="$(git rev-parse "$1^{commit}")"
	bodies="$(git log -F --grep="Refs: $2 -> $3" --format='%B' "$4" -- 2>/dev/null || true)"
	grep -qxF "Refs: $2 -> $3" <<<"$bodies" || return 1
	while IFS= read -r sha; do
		[ -n "$sha" ] || continue
		squashed=1
		if [ "$sha" = "$tip" ] || git merge-base --is-ancestor "$tip" "$sha" 2>/dev/null; then found=1; fi
	done < <(awk -v c="$2" '$1 == "Squashed:" && $2 == c { print $3 }' <<<"$bodies")
	[ "$squashed" = 0 ] || [ "$found" = 1 ]
}

# squashed_in_chain <tipref> <pref>: succeed when the tip of <tipref> is an ancestor of, or has no
# change left against (a simulated merge that changes nothing), any 'Squashed: <branch> <sha>'
# recorded on <pref>, whatever <branch> is. It covers a grandchild integrated by merge into a
# parent that was then squashed into the ORIGINAL.
# Arguments: $1 ref of the branch copy, $2 ref searched (a copy of the ORIGINAL). Returns: 0 in, 1 not.
squashed_in_chain() {
	local tip sha tree
	tip="$(git rev-parse "$1^{commit}" 2>/dev/null)" || return 1
	while IFS= read -r sha; do
		{ [ -n "$sha" ] && git cat-file -e "$sha^{commit}" 2>/dev/null; } || continue
		git merge-base --is-ancestor "$tip" "$sha" 2>/dev/null && return 0
		tree="$(git merge-tree --write-tree "$sha" "$tip" 2>/dev/null)" || continue
		[ "$(head -n1 <<<"$tree")" = "$(git rev-parse "$sha^{tree}")" ] && return 0
	done < <(git log -F --grep='Squashed: ' --format='%B' "$2" -- 2>/dev/null | awk '$1 == "Squashed:" { print $3 }')
	return 1
}

# squash_commit <child> <original> <pref>: print the short id of the commit of <pref> whose body
# has the line 'Refs: <child> -> <original>'. Returns: 0 and the id; 1 when there is none.
squash_commit() {
	local sha
	while IFS= read -r sha; do
		[ -n "$sha" ] || continue
		if git log -n1 --format=%B "$sha" | grep -qxF "Refs: $1 -> $2"; then
			git rev-parse --short "$sha"
			return 0
		fi
	done < <(git log -F --grep="Refs: $1 -> $2" --format=%H "$3" -- 2>/dev/null)
	return 1
}

# children_pending <original>: print, space separated, the direct children of <original> that
# are not integrated into it (branch_integrated). Arguments: $1 the '<F>/ORIGINAL' branch.
# Returns: 0; prints nothing when every child is in.
children_pending() {
	local p="$1" c out=""
	while IFS= read -r c; do
		[ -n "$c" ] || continue
		branch_integrated "$c" "$p" || out="$out $c"
	done < <(branch_children "$p")
	printf '%s' "${out# }"
}

# integrated_sha <child> <original>: print the short id of the squash commit of <original> that
# took <child> in ('Refs: <child> -> <original>'), when <child> is integrated that way (the same
# rule as branch_integrated) and its tip is not simply an ancestor of <original>: an empty branch
# that was just created from <original> is not "integrated", whatever its name once was.
# Arguments: $1 child branch, $2 ORIGINAL branch name (a local branch). Returns: 0 and prints the
# id; 1 when there is none (pending, or integrated only by ancestry).
integrated_sha() {
	local c="$1" p="$2" cref
	cref="$(best_ref "$c" || true)"
	[ -n "$cref" ] || return 1
	git merge-base --is-ancestor "$cref" "$p" 2>/dev/null && return 1
	branch_integrated "$c" "$p" || return 1
	squash_commit "$c" "$p" "$p"
}

# ---- TESTING sandbox guards (hooks and commands call these; the sandbox is scripts/git-testing.sh) ----

# Whether a branch is a TESTING sandbox: '<level>/TESTING' (the leaf is branches.testing_leaf), and
# only with branches.flow = squash (the sandbox is a 5.x feature; with the 4.x merge flow the leaf is
# an ordinary segment). A branch named just the leaf has no level and is an ordinary branch.
# Arguments: $1 branch. Returns: 0 when it is one, 1 otherwise.
is_testing_branch() {
	[ "${QS_BR_FLOW:-squash}" = squash ] || return 1
	case "$1" in ?*/"${QS_BR_TESTING:-TESTING}") return 0 ;; esac
	return 1
}

# The local TESTING sandboxes as full ref names. The glob 'refs/heads/**/<leaf>' also matches a
# branch named just <leaf>, so every match is checked with is_testing_branch.
# Arguments: none. Returns: 0; prints one 'refs/heads/...' line per sandbox (possibly none).
testing_local_refs() {
	local leaf="${QS_BR_TESTING:-TESTING}" ref
	while IFS= read -r ref; do
		is_testing_branch "${ref#refs/heads/}" && printf '%s\n' "$ref"
	done < <(git for-each-ref --format='%(refname)' "refs/heads/**/$leaf")
	return 0
}

# Whether a branch-name segment is the reserved TESTING leaf, ignoring case. Reserved only with
# branches.flow = squash (see is_testing_branch); the name check of valid_branch_name is
# reserved_segments_ok.
# Arguments: $1 segment. Returns: 0 when reserved, 1 otherwise.
testing_reserved_segment() {
	local a b
	[ "${QS_BR_FLOW:-squash}" = squash ] || return 1
	a="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
	b="$(printf '%s' "${QS_BR_TESTING:-TESTING}" | tr '[:upper:]' '[:lower:]')"
	[ "$a" = "$b" ]
}

# Print the refusal shown whenever a TESTING branch would be merged, rebased or integrated.
# Arguments: none. Returns: 0; the message goes to stderr.
testing_message() {
	echo "TESTING is a sandbox: it cannot be merged, rebased or integrated. Move its new commits to their source branches with 'git testing repartir'." >&2
}

# Refuse a command that runs on a TESTING branch (integra, subir).
# Arguments: $1 branch. Returns: 0 (message printed) when the branch is TESTING and the command
# must stop; 1 when the branch is not a sandbox.
testing_refused() {
	is_testing_branch "$1" || return 1
	testing_message
	return 0
}

# Hook guard for a merge: refused when the target or any source is a TESTING branch.
# Arguments: $1 target branch, $2 newline-separated names of the branches being merged.
# Returns: 0 (message printed) when the merge must be refused; 1 when it is not a sandbox merge.
testing_blocks_merge() {
	local s
	if is_testing_branch "$1"; then
		testing_message
		return 0
	fi
	while IFS= read -r s; do
		[ -n "$s" ] || continue
		if is_testing_branch "$s"; then
			testing_message
			return 0
		fi
	done <<<"$2"
	return 1
}

# After pre-merge-commit refused an automatic merge, git leaves the merge result staged. Put back
# exactly the paths the merge staged (git started the merge only if none of them had local
# changes), so a refused merge changes nothing. Does nothing while a merge is in progress (a
# conflicted merge being concluded by 'git commit').
# Arguments: none. Returns: 0.
testing_undo_merge() {
	local p
	[ -e "$(git rev-parse --git-path MERGE_HEAD)" ] && return 0
	while IFS= read -r -d '' p; do
		if git cat-file -e "HEAD:$p" 2>/dev/null; then
			git checkout -q HEAD -- "$p"
		else
			git rm -q -f --cached -- "$p"
			rm -f -- "$p"
		fi
	done < <(git diff --cached --name-only -z HEAD)
	return 0
}

# Hook guard for a rebase: refused when the rebased branch or the upstream is a TESTING branch.
# Arguments: $1 branch being rebased, $2 upstream as typed. Returns: 0 (message printed) when
# refused; 1 otherwise.
testing_blocks_rebase() {
	local up
	up="$(git rev-parse -q --symbolic-full-name "$2" 2>/dev/null || true)"
	up="${up#refs/heads/}"
	up="${up#refs/remotes/origin/}"
	if is_testing_branch "$1" || { [ -n "$up" ] && is_testing_branch "$up"; }; then
		testing_message
		return 0
	fi
	return 1
}

# Hook guard for a push: a TESTING branch may only be pushed to its own name.
# Arguments: $1 local ref as git gives it (refs/heads/x or HEAD), $2 remote ref.
# Returns: 0 (message printed) when refused; 1 otherwise.
testing_blocks_push() {
	local b
	case "$1" in
	refs/heads/*) b="${1#refs/heads/}" ;;
	HEAD) b="$(current_branch || true)" ;;
	*) return 1 ;;
	esac
	is_testing_branch "$b" || return 1
	case "$2" in refs/heads/*) is_testing_branch "$2" && return 1 ;; *) return 1 ;; esac
	testing_message
	return 0
}

# Release helper: whether a TESTING branch can be deleted with its tree (no undistributed
# commits). A TESTING branch with undistributed commits is not "ok": the caller sets it aside as
# unmerged and a warning names the commits. Loads scripts/git-testing.sh on demand.
# Arguments: $1 branch. Returns: 0 when it is a TESTING branch that is safe to delete; 1 when it
# is not a TESTING branch or has undistributed commits.
testing_release_ok() {
	is_testing_branch "$1" || return 1
	# shellcheck source=scripts/git-testing.sh
	. "$(dirname "${BASH_SOURCE[0]}")/git-testing.sh"
	tst_release_ok "${1%/*}"
}

# Build the revision arguments of a range of commits into the global array TST_RANGE.
# Arguments: $1 new tip, $2 old tip (all zeros or empty: a new ref), $3 scope used for a new ref:
# 'remotes' (history not on any remote) or 'branches:<name>' (history not on any other local
# branch; <name> is the updated branch). TESTING branches never count as "other".
# Returns: 0; sets TST_RANGE.
testing_range() {
	local new="$1" old="${2:-}" scope="${3:-remotes}" leaf="${QS_BR_TESTING:-TESTING}"
	if [ -n "$old" ] && [ -n "${old//0/}" ] && git cat-file -e "${old}^{commit}" 2>/dev/null; then
		TST_RANGE=("$new" "^$old")
	else
		case "$scope" in
		branches:*) TST_RANGE=("$new" --not --exclude="${scope#branches:}" --exclude="*/$leaf" --branches) ;;
		*) TST_RANGE=("$new" --not --exclude="*/$leaf" --remotes) ;;
		esac
	fi
}

# The marker commit of a TESTING history: its newest first-parent 'Testing-Create:' commit.
# Arguments: $1 tip. Returns: 0 and prints the sha; 1 when there is no marker.
testing_marker_of() {
	local m
	m="$(git log --first-parent -n1 --format=%H --grep='^Testing-Create: ' "$1" 2>/dev/null || true)"
	[ -n "$m" ] || return 1
	printf '%s' "$m"
}

# Find a TESTING commit inside a range of commits: a marker commit (trailers 'Testing-Create:' and
# 'Sources:') or a commit made on a local TESTING branch after its marker (first-parent, so what
# was merged into TESTING by hand never counts as made there). This is how TESTING content is
# detected when it reached a non-TESTING branch without a merge hook (fast-forward).
# Arguments: $1 new tip, $2 old tip (all zeros or empty: a new ref), $3 scope used for a new ref
# (see testing_range). Returns: 0 and prints the offending sha when there is one; 1 when clean.
testing_leak_in_range() {
	local hit t m
	local TST_RANGE=()
	testing_range "$1" "${2:-}" "${3:-remotes}"
	hit="$(git log -n1 --format=%H --all-match --grep='^Testing-Create: ' --grep='^Sources:$' "${TST_RANGE[@]}" 2>/dev/null || true)"
	if [ -n "$hit" ]; then
		printf '%s' "$hit"
		return 0
	fi
	# commits made on a TESTING branch after its marker, found in the range (marker already shipped)
	[ -n "$(git rev-list -n1 "${TST_RANGE[@]}" 2>/dev/null)" ] || return 1
	while IFS= read -r t; do
		m="$(testing_marker_of "$t")" || continue
		hit="$(comm -12 <(git rev-list -n 2000 "${TST_RANGE[@]}" 2>/dev/null | sort) \
			<(git rev-list --first-parent --no-merges -n 2000 "$m..$t" 2>/dev/null | sort) | head -n1)"
		if [ -n "$hit" ]; then
			printf '%s' "$hit"
			return 0
		fi
	done < <(testing_local_refs)
	return 1
}

# Delete the cached patch-id lists whose tip is no longer the tip of any local TESTING branch.
# One for-each-ref call and a look at the file names: cheap enough to run on every cache write.
# Temporary files of a write in progress (a dot after the tip) are left alone.
# Arguments: $1 cache folder, $2 tip just written (always kept). Returns: 0.
testing_prune_pids() {
	local dir="$1" live=" $2 " f tip sha ref
	while read -r sha ref; do
		is_testing_branch "${ref#refs/heads/}" && live="$live$sha "
	done < <(git for-each-ref --format='%(objectname) %(refname)' refs/heads/)
	for f in "$dir"/tst-pids-*; do
		[ -e "$f" ] || continue
		tip="${f##*/tst-pids-}"
		case "$tip" in *.*) continue ;; esac
		case "$live" in *" $tip "*) ;; *) rm -f -- "$f" ;; esac
	done
	return 0
}

# The stable patch-ids of the commits made on a TESTING branch (first-parent, non-merge, after its
# marker). Cached by the tip sha in the git dir, so a push computes them once. A failed git
# command is never cached (an empty list would then pass every copy check); a write prunes the
# cache files of tips that are no longer a TESTING tip (testing_prune_pids).
# Arguments: $1 tip sha. Returns: 0 and prints '<patch-id> <commit sha>' lines (possibly none);
# 1 when git failed (nothing printed, nothing cached).
testing_patch_ids() {
	local tip="$1" m dir cache log tmp ok=0
	dir="$(git rev-parse --absolute-git-dir)/quality-suite"
	cache="$dir/tst-pids-$tip"
	if [ -f "$cache" ]; then
		cat "$cache"
		return 0
	fi
	m="$(testing_marker_of "$tip")" || return 0
	mkdir -p "$dir"
	log="$cache.log.$$"
	tmp="$cache.$$"
	# why: a pipe would show only the status of patch-id; each command's status is checked here
	if git log --first-parent --no-merges -p --format='commit %H' "$m..$tip" >"$log" 2>/dev/null &&
		git patch-id --stable <"$log" >"$tmp" 2>/dev/null; then
		ok=1
	fi
	rm -f -- "$log"
	if [ "$ok" = 1 ]; then
		mv -f "$tmp" "$cache"
		testing_prune_pids "$dir" "$tip"
		cat "$cache"
		return 0
	fi
	rm -f -- "$tmp"
	return 1
}

# Find a copy of TESTING work in a range of commits that did not travel through 'git testing
# repartir': a commit whose stable patch-id equals the one of a commit made on a local TESTING
# branch (this catches 'git cherry-pick' without -x, a rebase of TESTING commits, and a squash
# of a single TESTING commit). A match is fine when the commit message names that TESTING commit
# in a '(cherry picked from commit <sha>)' line (what repartir writes) or when the TESTING commit
# is recorded as distributed. A squash merge of TESTING is refused earlier, at commit time
# (testing_squash_hit). Limit: a hand-made copy of several TESTING commits in one commit has a
# combined patch-id no single commit has, and is not recognised; comparing combined diffs would
# also flag the legitimate result of a full distribution, so it is not done.
# Arguments: $1 new tip, $2 old tip, $3 scope (see testing_range).
# Returns: 0 and prints '<commit> <TESTING commit>' for the first offender; 1 when clean.
testing_copy_in_range() {
	local all rng t c cand body rc=1 hit
	local TST_RANGE=()
	all="$(mktemp)"
	rng="$(mktemp)"
	while IFS= read -r t; do
		# why: a failed patch-id is not cached (testing_patch_ids); the other sandboxes still count
		testing_patch_ids "$(git rev-parse "$t")" >>"$all" || true
	done < <(testing_local_refs)
	if [ -s "$all" ]; then
		testing_range "$1" "${2:-}" "${3:-remotes}"
		git log --no-merges -p -n 500 --format='commit %H' "${TST_RANGE[@]}" 2>/dev/null |
			git patch-id --stable >"$rng" || true
		hit="$(awk 'NR == FNR { a[$1] = a[$1] " " $2; next } $1 in a { print $2 a[$1] }' "$all" "$rng")"
		while read -r c cand; do
			[ -n "$c" ] || continue
			body="$(git log -n1 --format=%B "$c")"
			for t in $cand; do
				grep -qF "(cherry picked from commit $t)" <<<"$body" && continue
				git config --get-regexp '^qs\.testing\..*\.distributed$' 2>/dev/null | grep -q " $t " && continue
				printf '%s %s' "$c" "$t"
				rc=0
				break 2
			done
		done <<<"$hit"
	fi
	rm -f "$all" "$rng"
	return "$rc"
}

# Find a merge made INTO a TESTING branch after its creation (first-parent merge commit after the
# marker). TESTING is recreated ('git testing crear --recrear'), never merged into.
# Arguments: $1 TESTING tip. Returns: 0 and prints the merge sha when there is one; 1 otherwise.
testing_merged_into() {
	local m hit
	m="$(testing_marker_of "$1")" || return 1
	hit="$(git rev-list --first-parent --merges -n1 "$m..$1" 2>/dev/null || true)"
	[ -n "$hit" ] || return 1
	printf '%s' "$hit"
}

# Find TESTING work in the squash commit being made. 'git merge --squash' leaves .git/SQUASH_MSG:
# the header 'Squashed commit of the following:' and one 'commit <sha>' line per squashed commit.
# A commit is that squash only when its message uses SQUASH_MSG: the header line and every listed
# sha are in the message. A commit with its own message ('git commit -m') is not the squash. A
# SQUASH_MSG that lists TESTING work but is not used by this commit is stale (left by an aborted
# squash): it is ignored and a one-line note says it can be deleted. The listed commits are
# TESTING work when one is a TESTING marker commit or a commit made on a local TESTING branch
# (first-parent, after its marker).
# Arguments: $1 the commit message as it will be stored. Returns: 0 and prints the first offending
# listed sha when this commit is the squash of TESTING work; 1 otherwise.
testing_squash_hit() {
	local f t m sha own="" hit="" uses=0 msg="$1"
	f="$(git rev-parse --git-path SQUASH_MSG)"
	[ -f "$f" ] || return 1
	while IFS= read -r t; do
		m="$(testing_marker_of "$t")" || continue
		own="$own $(git rev-list --first-parent --no-merges "$m..$t" 2>/dev/null | tr '\n' ' ')"
	done < <(testing_local_refs)
	while IFS= read -r sha; do
		if git log -n1 --format=%B "$sha" 2>/dev/null | grep -q '^Testing-Create: ' ||
			grep -qw "$sha" <<<"$own"; then
			hit="$sha"
			break
		fi
	done < <(sed -n 's/^commit \([0-9a-f]\{40\}\)$/\1/p' "$f")
	[ -n "$hit" ] || return 1
	# why: the message must be the squash's own: the header and every listed sha are in it
	if grep -qxF 'Squashed commit of the following:' <<<"$msg"; then
		uses=1
		while IFS= read -r sha; do
			grep -qF "$sha" <<<"$msg" || uses=0
		done < <(sed -n 's/^commit \([0-9a-f]\{40\}\)$/\1/p' "$f")
	fi
	if [ "$uses" = 1 ]; then
		printf '%s' "$hit"
		return 0
	fi
	echo "commit-msg: .git/SQUASH_MSG is stale (this commit does not use it): rm .git/SQUASH_MSG" >&2
	return 1
}

# POM_AWK: awk program that walks a pom.xml tracking the element path (comments skipped). With
# mode=art it prints the project artifactId. With mode=strip it drops the lines that only hold the
# project's own version: project/version, project/properties/revision and project/parent/version
# when the parent artifactId is listed in "ours" ("|a|b|"). Anything else is kept. With mode=mask
# each such line is printed as the line held in "token" instead, and the line itself is appended
# to the file named by "saved" (git publicar solves release-line conflicts this way).
# why: awk variables such as $0 must reach awk unexpanded
# shellcheck disable=SC2016
POM_AWK='
function top(   i, p) { p = ""; for (i = 1; i <= n; i++) p = p "/" st[i]; return substr(p, 2) }
{
	line = $0; rest = line; full = 0
	if (line ~ /^[ \t\r]*<(version|revision)>[^<]*<\/(version|revision)>[ \t\r]*$/) full = 1
	drop = 0
	while (rest != "") {
		if (incom) {
			i = index(rest, "-->")
			if (!i) break
			rest = substr(rest, i + 3); incom = 0; continue
		}
		if (substr(rest, 1, 4) == "<!--") { incom = 1; rest = substr(rest, 5); continue }
		if (match(rest, /^<[^>]*>/)) {
			tag = substr(rest, 1, RLENGTH); rest = substr(rest, RLENGTH + 1)
			if (tag ~ /^<[?!]/ || tag ~ /\/>$/) continue
			if (tag ~ /^<\//) {
				name = substr(tag, 3, length(tag) - 3); sub(/[ \t\r].*/, "", name)
				p = top()
				if (full && n > 0 && st[n] == name && txt != "") {
					if (p == "project/version" || p == "project/properties/revision") drop = 1
					else if (p == "project/parent/version" && index(ours, "|" parent "|")) drop = 1
				}
				if (p == "project/artifactId" && mode == "art") print txt
				if (p == "project/parent/artifactId") parent = txt
				if (n > 0) n--
				txt = ""
			} else {
				name = substr(tag, 2, length(tag) - 2); sub(/[ \t\r\n\/].*/, "", name)
				st[++n] = name; txt = ""
			}
			continue
		}
		if (match(rest, /^[^<]+/)) { txt = txt substr(rest, 1, RLENGTH); rest = substr(rest, RLENGTH + 1); continue }
		break
	}
	gsub(/^[ \t\r]+|[ \t\r]+$/, "", txt)
	if (mode == "mask" && drop) { print token; print line >>saved }
	else if ((mode == "strip" && !drop) || mode == "mask") print line
}'

# JSON_AWK: awk program that drops the top-level "version" line of a package.json (depth 1, whole
# line `"version": "..."`). Dependencies and any nested "version" key are kept. With mode=mask
# that line is printed as "token" and appended to the file named by "saved" (as POM_AWK).
# why: used by the scripts that source this library (git-unmerged.sh, git-rama.sh)
# shellcheck disable=SC2016,SC2034
JSON_AWK='
{
	line = $0
	if (depth == 1 && line ~ /^[ \t\r]*"version"[ \t]*:[ \t]*"([^"\\]|\\.)*"[ \t]*,?[ \t\r]*$/) {
		if (mode == "mask") { print token; print line >>saved }
	} else print line
	ins = 0
	for (i = 1; i <= length(line); i++) {
		c = substr(line, i, 1)
		if (ins) { if (c == "\\") i++; else if (c == "\"") ins = 0; continue }
		if (c == "\"") ins = 1
		else if (c == "{" || c == "[") depth++
		else if (c == "}" || c == "]") depth--
	}
}'

# pom_artifacts REF: print "|a|b|", the artifactIds of every pom.xml in the tree of REF.
pom_artifacts() {
	local f out="|"
	while IFS= read -r f; do
		out+="$(git show "$1:$f" 2>/dev/null | awk -v mode=art "$POM_AWK" | head -1)|"
	done < <(git ls-tree -r --name-only "$1" 2>/dev/null | grep -E '(^|/)pom\.xml$' || true)
	printf '%s' "$out"
}
