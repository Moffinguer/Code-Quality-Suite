#!/usr/bin/env bash
# special-lib.sh - names and placement of the special branches (6.0.0 branches.special table).
# Sourced by git-flow-lib.sh; it reads QS_SP_NAMES and QS_SP_<TYPE>_<PROP> (qs_special_defaults
# or the policy.env written by the engine) and the QS_BR_* policy. Special branches exist only
# with branches.flow = squash: with the 4.x merge flow every function here says "not special".
# Special segments (DOCS, ATTEMPT-2, REVIEW-a...) do not count for branches.levels, like ORIGINAL.

# Print the value of a QS_SP_<TYPE>_<PROP> variable.
# Arguments: $1 type (DOCS...), $2 property (AT, CHILDREN, SUFFIX...). Returns: 0; prints it.
special_prop() {
	local v="QS_SP_${1}_${2}"
	printf '%s' "${!v:-}"
}

# Whether special branches are in force and a type is enabled in the table.
# Arguments: $1 type. Returns: 0 when enabled and the flow is squash; 1 otherwise.
special_enabled() {
	[ "${QS_BR_FLOW:-squash}" = squash ] || return 1
	case " ${QS_SP_NAMES:-} " in *" $1 "*) return 0 ;; esac
	return 1
}

# The type a path segment is reserved for, ignoring case: an enabled fixed name (DOCS) or the
# prefix of an enabled suffixed one (ATTEMPT-3, review-a).
# Arguments: $1 segment. Returns: 0; prints the type (nothing when the segment is ordinary).
special_segment_type() {
	local s t u
	s="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
	for t in ${QS_SP_NAMES:-}; do
		special_enabled "$t" || continue
		u="$(special_prop "$t" SUFFIX)"
		if [ "$u" = none ]; then
			if [ "$s" = "$t" ]; then
				printf '%s' "$t"
				return 0
			fi
		else
			case "$s" in "$t"-*)
				printf '%s' "$t"
				return 0
				;;
			esac
		fi
	done
	return 0
}

# The command that creates a type of special branch (the user is sent there, not to git np/nr).
# Arguments: $1 type. Returns: 0; prints the command.
special_command() {
	case "$1" in
	MIGRATION) echo "git migracion" ;;
	DOCS) echo "git docs" ;;
	REFACTOR) echo "git refactor" ;;
	TESTS) echo "git tests" ;;
	FORMAT) echo "git formatear" ;;
	SPIKE) echo "git spike" ;;
	ATTEMPT) echo "git intentos" ;;
	REVIEW) echo "git revision" ;;
	QUARANTINE) echo "git cuarentena" ;;
	CHECKPOINT) echo "git checkpoint" ;;
	*) echo "the creation command of $1" ;;
	esac
}

# Whether any segment of a branch name is reserved for an enabled special type.
# Arguments: $1 branch. Returns: 0 when one is; 1 otherwise.
special_has_segment() {
	local seg
	while IFS= read -r seg; do
		[ -n "$(special_segment_type "$seg")" ] && return 0
	done < <(tr '/' '\n' <<<"$1")
	return 1
}

# Refusal text for a creation command (git np, nr, es) given a name segment.
# Arguments: $1 segment. Returns: 0 and prints "'<segment>' is reserved for <TYPE> branches: use
# '<command>'" when the segment is reserved for an enabled special type; 1 and nothing otherwise.
special_refusal() {
	local t
	t="$(special_segment_type "$1")"
	[ -n "$t" ] || return 1
	echo "'$1' is reserved for $t branches: use '$(special_command "$t")'"
}

# Refusal text for a node path of 'git es' whose segments include a special name.
# Arguments: $1 node path. Returns: 0 and prints the refusal for the first such segment; 1 and
# nothing when no segment is reserved for an enabled special type.
special_node_refusal() {
	local seg
	while IFS= read -r seg; do
		special_refusal "$seg" && return 0
	done < <(tr '/' '\n' <<<"$1")
	return 1
}

# Check one special segment of a branch name: its exact name and its placement.
# Arguments: $1 segment, $2 type, $3 number of ordinary segments before it, $4 enclosing special
# type (empty when none). Returns: 0 when fine; 1 with the reason in SP_WHY otherwise.
special_segment_ok() {
	local seg="$1" t="$2" lvl="$3" under="$4" sfx at rest
	sfx="$(special_prop "$t" SUFFIX)"
	at="$(special_prop "$t" AT)"
	case "$sfx" in
	none)
		[ "$seg" = "$t" ] || {
			SP_WHY="'$seg' is reserved for $t: only '$t' exactly ($(special_command "$t"))"
			return 1
		}
		;;
	n)
		printf '%s' "$seg" | grep -qE -- "^$t-[0-9]+\$" || {
			SP_WHY="'$seg' is reserved for $t: only '$t-<n>' exactly ($(special_command "$t"))"
			return 1
		}
		;;
	*)
		rest="${seg#"$t"-}"
		if [ "${seg%%-*}" != "$t" ] || [ -z "$rest" ] || ! printf '%s' "$rest" | grep -qE -- "$(_br_level_re $((lvl + 1)))"; then
			SP_WHY="'$seg' is reserved for $t: only '$t-<task>' exactly ($(special_command "$t"))"
			return 1
		fi
		;;
	esac
	case "$at" in
	version)
		if [ "$lvl" -ne 1 ] || [ -n "$under" ]; then
			SP_WHY="$t goes only directly under the version: <version>/$t"
			return 1
		fi
		;;
	node)
		[ "$lvl" -ge 2 ] || {
			SP_WHY="$t goes only under a node: <version>/<ot>/$t"
			return 1
		}
		;;
	task)
		if [ "$sfx" = n ] && [ "$lvl" -lt 3 ]; then
			SP_WHY="$t goes only under a task: <node>/<task>/$t-<n>"
			return 1
		fi
		if [ "$sfx" != n ] && [ "$lvl" -lt 2 ]; then
			SP_WHY="$t goes only next to a task: <node>/$t-<task>"
			return 1
		fi
		;;
	esac
	return 0
}

# Check a branch name against the special table: the exact name of each special segment, its
# placement (at: version, node or task; children), and the ordinary segments around it against
# branches.levels (special segments are not levels). Sets SP_TYPE (the outermost special type)
# and SP_WHY (the reason when refused).
# Arguments: $1 branch. Returns: 0 valid; 1 refused; 2 the name has no special segment.
# shellcheck disable=SC2034 # why: SP_TYPE and SP_WHY are read by the callers
special_parse() {
	local b="$1" segs=() n i seg t lvl=0 under="" rx
	SP_TYPE="" SP_WHY=""
	special_has_segment "$b" || return 2
	IFS=/ read -ra segs <<<"$b"
	n="${#segs[@]}"
	for ((i = 0; i < n; i++)); do
		seg="${segs[$i]}"
		t="$(special_segment_type "$seg")"
		if [ -n "$under" ] && [ "$(special_prop "$under" CHILDREN)" != 1 ]; then
			SP_WHY="a $under branch has no children"
			return 1
		fi
		if [ -n "$t" ]; then
			special_segment_ok "$seg" "$t" "$lvl" "$under" || return 1
			[ -n "$SP_TYPE" ] || SP_TYPE="$t"
			under="$t"
			continue
		fi
		if [ "$seg" = "$QS_BR_LEAF" ]; then
			[ "$i" -eq $((n - 1)) ] || {
				SP_WHY="'$QS_BR_LEAF' can only be the last segment"
				return 1
			}
			continue
		fi
		[ "$i" -eq $((n - 1)) ] && [ "$seg" = "${QS_BR_TESTING:-TESTING}" ] && continue
		if reserved_leaf_segment "$seg"; then
			SP_WHY="'$seg' is reserved ($QS_BR_LEAF, $QS_BR_RELEASE_LEAF and ${QS_BR_TESTING:-TESTING}, in any case)"
			return 1
		fi
		rx="$(_br_level_re $((lvl + 1)))"
		printf '%s' "$seg" | grep -qE -- "$rx" || {
			SP_WHY="segment '$seg' does not match $rx"
			return 1
		}
		lvl=$((lvl + 1))
	done
	return 0
}

# The special type of a branch: that of its outermost special segment, for the branch itself and
# everything below it (6.0.0/MIGRATION/java17 is MIGRATION).
# Arguments: $1 branch. Returns: 0; prints the type, nothing for an ordinary branch, a
# misplaced name or a disabled type.
special_kind() {
	special_parse "$1" || return 0
	printf '%s' "$SP_TYPE"
}

# The parent of a special branch when it is not the ORIGINAL of its node: REVIEW-<task> and
# CHECKPOINT-<task> hang from the task (its branch, or its ORIGINAL once the task has attempts).
# Arguments: $1 branch. Returns: 0; prints the parent (nothing when the generic rule applies).
special_parent() {
	local b="$1" node seg t task pre
	node="${b%/"$QS_BR_LEAF"}"
	seg="${node##*/}"
	t="$(special_segment_type "$seg")"
	case "$t" in REVIEW | CHECKPOINT) ;; *) return 0 ;; esac
	[ -n "$(special_kind "$b")" ] || return 0
	task="${seg#*-}"
	pre="${node%/*}"
	if ! git show-ref --verify -q "refs/heads/$pre/$task" && ! git show-ref --verify -q "refs/remotes/origin/$pre/$task" &&
		{ git show-ref --verify -q "refs/heads/$pre/$task/$QS_BR_LEAF" || git show-ref --verify -q "refs/remotes/origin/$pre/$task/$QS_BR_LEAF"; }; then
		echo "$pre/$task/$QS_BR_LEAF"
	else echo "$pre/$task"; fi
}

# The marker 'git arbol' prints after a branch of a special type (and for TESTING).
# Arguments: $1 branch. Returns: 0; prints " [docs]" and the like, nothing for an ordinary branch.
special_marker() {
	local t
	t="$(special_kind "$1")"
	if [ -n "$t" ]; then
		printf ' [%s]' "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
	elif is_testing_branch "$1"; then printf ' [testing]'; fi
	return 0
}

# Warning lines of 'git arbol' for versions that have an open MIGRATION (one line per version).
# Arguments: $1 optional prefix (a version) to restrict to. Returns: 0.
special_arbol_warnings() {
	local prefix="${1:-}" v
	special_enabled MIGRATION || return 0
	{
		git for-each-ref --format='%(refname:short)' refs/heads/
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/
	} | awk -F/ -v p="$prefix" '$2 == "MIGRATION" && (p == "" || $1 == p) { print $1 }' | sort -u |
		while IFS= read -r v; do
			printf '! %s: MIGRATION open: nothing else can be created\n' "$v"
		done
	return 0
}

# The open MIGRATION of a version, local or only on origin: '<v>/MIGRATION' or '<v>/MIGRATION/...'.
# Arguments: $1 version. Returns: 0 and prints '<v>/MIGRATION' when the version has one; 1 when
# MIGRATION is disabled or the version has none.
special_migration_open() {
	local v="$1" r
	special_enabled MIGRATION || return 1
	for r in refs/heads refs/remotes/origin; do
		if git show-ref --verify -q "$r/$v/MIGRATION" ||
			[ -n "$(git for-each-ref --count=1 "$r/$v/MIGRATION/")" ]; then
			printf '%s/MIGRATION' "$v"
			return 0
		fi
	done
	return 1
}

# The MIGRATION lock: while a version has an open MIGRATION nothing else can be created in it
# (git np, nr, es, nv, docs, testing crear), except inside the MIGRATION subtree itself.
# Arguments: $1 version, $2 the branch about to be created (empty when unknown). Returns: 0 and
# prints the refusal when the version is locked for that branch; 1 when it is free.
special_migration_lock() {
	local v="$1" b="${2:-}" m
	case "$b" in "$v"/MIGRATION | "$v"/MIGRATION/*) return 1 ;; esac
	m="$(special_migration_open "$v")" || return 1
	echo "$v has an open MIGRATION ($m): nothing else can be created until it is integrated (git integra) or deleted"
}

# One-line summary of the rules of a special type, for the post-checkout hook.
# Arguments: $1 type. Returns: 0; prints "at <at>, integrates <how>, order <o>, ..." with only
# the properties that are set.
special_summary() {
	local t="$1" p v out
	out="at $(special_prop "$t" AT), integrates $(special_prop "$t" INTEGRATES), order $(special_prop "$t" ORDER)"
	for p in TYPES PATHS LEVEL TRAILERS; do
		v="$(special_prop "$t" "$p")"
		[ -z "$v" ] || out="$out, $(printf '%s' "$p" | tr '[:upper:]' '[:lower:]') $v"
	done
	[ "$(special_prop "$t" PUSH)" = normal ] || out="$out, push $(special_prop "$t" PUSH)"
	printf '%s' "$out"
}

# --- hook rules (6.0.0 hooks_rules): the checks of pre-commit, commit-msg and pre-push, all read
# from the table (QS_SP_<TYPE>_<PROP>). A rule is refused only for the branch's own special type.

# Expand the @tokens of a paths value into globs, one per line. It mirrors PATH_TOKENS of
# engine/policy.py (tests/unit/test_special_hooks.py compares both).
# Arguments: $1 a paths value: globs and @tokens joined with '|' (as QS_SP_<TYPE>_PATHS holds it).
# Returns: 0; prints the globs in order, an unknown @token as is.
special_expand_paths() {
	local repo='README.md|CHANGELOG.md|CONTRIBUTING.md|CODE_OF_CONDUCT.md|SECURITY.md|SUPPORT.md|CONTRIBUTORS.md|MAINTAINERS.md|ROADMAP.md|FAQ.md|INSTALL.md|ARCHITECTURE.md|API.md|DEVELOPMENT.md|AUTHORS|LICENSE|CODEOWNERS|CITATION.cff'
	local tests='src/test/**|**/test/**|**/tests/**|**/*_test.*|**/test_*.py|**/*.spec.*|**/*.test.*'
	local item list=() parts=() rep=() tst=()
	IFS='|' read -ra parts <<<"$1"
	IFS='|' read -ra rep <<<"$repo"
	IFS='|' read -ra tst <<<"$tests"
	for item in ${parts[@]+"${parts[@]}"}; do
		case "$item" in
		@repo-files) list+=("${rep[@]}") ;;
		@docs) list+=('*.md' '**/*.md' 'docs/**' "${rep[@]}") ;;
		@tests) list+=("${tst[@]}") ;;
		*) list+=("$item") ;;
		esac
	done
	printf '%s\n' "${list[@]}" | awk '!seen[$0]++'
}

# Translate a glob into an extended regular expression: '**/' any folders, '**' anything, '*'
# anything but '/', '?' one character but '/'.
# Arguments: $1 glob. Returns: 0; prints the anchored regex.
special_glob_regex() {
	local g="$1" out="^" c i n="${#1}"
	for ((i = 0; i < n; i++)); do
		c="${g:i:1}"
		case "$c" in
		'*')
			if [ "${g:i:2}" = '**' ]; then
				if [ "${g:i+2:1}" = / ]; then
					out+='(.*/)?'
					i=$((i + 2))
				else
					out+='.*'
					i=$((i + 1))
				fi
			else out+='[^/]*'; fi
			;;
		'?') out+='[^/]' ;;
		'.' | '+' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|') out+="\\$c" ;;
		*) out+="$c" ;;
		esac
	done
	printf '%s$' "$out"
}

# Whether a path matches any glob of a list.
# Arguments: $1 path, $2.. globs. Returns: 0 when one matches; 1 otherwise.
special_path_match() {
	local p="$1" g re
	shift
	for g in "$@"; do
		re="$(special_glob_regex "$g")"
		[[ $p =~ $re ]] && return 0
	done
	return 1
}

# The gate level a special type imposes on its branches.
# Arguments: $1 branch. Returns: 0; prints the level (nothing for an ordinary branch or a type
# with level null).
special_gate_level() {
	local t
	t="$(special_kind "$1")"
	[ -n "$t" ] || return 0
	special_prop "$t" LEVEL
}

# Whether a merge, squash, cherry-pick or rebase is in progress: the suite and git make those
# commits; the rules of a type apply to the commits a person makes.
# Arguments: none. Returns: 0 when one is in progress; 1 otherwise.
special_in_progress() {
	local f
	for f in MERGE_HEAD SQUASH_MSG CHERRY_PICK_HEAD rebase-merge rebase-apply; do
		[ -e "$(git rev-parse --git-path "$f")" ] && return 0
	done
	return 1
}

# Whether the badge between the qs:version markers of the README differs in the index and HEAD.
# Arguments: none. Returns: 0 when it differs; 1 otherwise.
special_badge_changed() {
	local rx='<!-- qs:version -->.*<!-- /qs:version -->' old new
	old="$(git show "HEAD:$QS_BR_README" 2>/dev/null | grep -o "$rx" || true)"
	new="$(git show ":$QS_BR_README" 2>/dev/null | grep -o "$rx" || true)"
	[ "$old" != "$new" ]
}

# Check the staged files of a commit against the table: paths of the type; the changelog and the
# README badge only on DOCS (DOCS mode: DOCS enabled with on_release required).
# Arguments: $1 branch, $2.. the staged paths (added, changed, renamed, deleted). Returns: 0 when
# fine; 1 and one line per problem on stdout otherwise.
special_check_staged() {
	local b="$1" t f paths=() g bad=0 docs_mode=0
	shift
	t="$(special_kind "$b")"
	g=""
	[ -z "$t" ] || g="$(special_prop "$t" PATHS)"
	if [ -n "$g" ]; then
		mapfile -t paths < <(special_expand_paths "$g")
		for f in "$@"; do
			special_path_match "$f" "${paths[@]}" && continue
			echo "$f: not allowed on a $t branch (paths: $g)"
			bad=1
		done
	fi
	if special_enabled DOCS && [ "$(special_prop DOCS ON_RELEASE)" = required ]; then docs_mode=1; fi
	if [ "$docs_mode" = 1 ] && [ "$t" != DOCS ] && ! is_release_branch "$b" && ! is_ot_release_branch "$b" && ! is_mainline "$b" && ! is_archived_branch "$b"; then
		for f in "$@"; do
			[ "$f" = "$QS_BR_CHANGELOG" ] || continue
			echo "$f: only the DOCS branch writes the changelog (git docs)"
			bad=1
		done
		if printf '%s\n' "$@" | grep -qxF -- "$QS_BR_README" && special_badge_changed; then
			echo "$QS_BR_README: the version badge changes only on the DOCS branch (git docs)"
			bad=1
		fi
	fi
	return "$bad"
}

# Check the Conventional Commits type of a message against the allowed types of a special type.
# Arguments: $1 type (special), $2 subject. Returns: 0 when allowed (or when the subject has no
# type: the conventional check reports it); 1 and the reason on stdout otherwise.
special_check_commit_type() {
	local t="$1" ct allowed
	ct="$(printf '%s' "$2" | sed -nE 's/^([a-z]+)(\([^)]*\))?!?: .*/\1/p')"
	[ -n "$ct" ] || return 0
	allowed="$(special_prop "$t" TYPES)"
	[ "$allowed" != '*' ] || return 0
	case "|$allowed|" in
	*"|$ct|"*) return 0 ;;
	esac
	if [ -z "$allowed" ]; then
		echo "a $t branch takes no commits of its own"
	else
		echo "type '$ct' is not allowed on a $t branch (allowed: ${allowed//|/, })"
	fi
	return 1
}

# Check the trailers a special type requires on every commit of its own.
# Arguments: $1 type, $2 the commit message. Returns: 0 when all are present; 1 and one line per
# missing trailer on stdout otherwise.
special_check_trailers() {
	local t="$1" msg="$2" tr bad=0 list
	list="$(special_prop "$t" TRAILERS)"
	[ -n "$list" ] || return 0
	local IFS='|'
	for tr in $list; do
		printf '%s\n' "$msg" | grep -qiE "^${tr}:[[:space:]]*[^[:space:]]" && continue
		echo "missing trailer '$tr:' (required on $t branches)"
		bad=1
	done
	return "$bad"
}
