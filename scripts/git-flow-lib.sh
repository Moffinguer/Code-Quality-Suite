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
	QS_COMMIT_SUBJECT_MAX=50 QS_COMMIT_CONVENTIONAL=1
	QS_BR_ENFORCE=block QS_BR_LEAF=ORIGINAL QS_BR_MAINLINE=develop QS_BR_PROTECTED='main master develop'
	QS_BR_SEGMENT='^[A-Za-z0-9][A-Za-z0-9_-]*$' QS_BR_LEAF_MERGE=merge QS_BR_REQUIRE_CHILDREN=1
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
# 'unmerged/<name>': a branch set aside by 'git release' because it was never integrated
is_archived_branch() {
	case "$1" in "$QS_BR_ARCHIVE"/?*) return 0 ;; esac
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
	if is_release_branch "$b"; then
		echo "$QS_BR_MAINLINE"
		return 0
	fi
	is_archived_branch "$b" && return 0 # set aside: no parent
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
	{ is_release_branch "$b" || is_archived_branch "$b"; } && return 0
	for ((i = 1; i <= ${QS_BR_ALLOW:-0}; i++)); do
		rx="QS_BR_ALLOW_$i"
		printf '%s' "$b" | grep -qE -- "${!rx}" && return 0
	done
	if LC_ALL=C grep -q '[^ -~]' <<<"$b"; then
		echo "only ASCII characters are allowed"
		return 1
	fi
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
		awk -v f="$f/" -v leaf="$QS_BR_LEAF" -v me="$p" '
        index($0, f) == 1 { r = substr($0, length(f) + 1); n = split(r, a, "/");
          if ($0 != me && (n == 1 || (n == 2 && a[2] == leaf))) print $0 }' | sort -u
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
	git config alias.encoding "!bash '$suite/scripts/qs-run.sh' --encoding"
	# why: develop has no qs-alias auto-registration yet (6.0.0): register it by hand until then
	git config alias.configurar-github "!bash '$suite/scripts/gh-settings.sh'"
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
