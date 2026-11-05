#!/usr/bin/env bash
# git-testing.sh (git alias: git testing) - the TESTING sandbox, one reserved leaf '<level>/TESTING'.
#   git testing crear <branch...> [--nivel <F>] [--recrear [--force]]
#       TESTING starts at '<F>/ORIGINAL' and gets each source branch (ANY branch) merged in, in order,
#       then an empty marker commit 'chore(testing): create' whose body lists the sources
#       ('Sources:' + '<branch> <sha>' lines, the source of truth; git config
#       qs.testing.<F>.sources is a cache rebuilt from it). The commits are made with plumbing
#       (merge-tree + commit-tree): no hook runs and the current branch and work tree do not change.
#       --recrear builds it again from the current ORIGINAL and sources (the recorded ones when none
#       are given); refused while TESTING has undistributed commits, unless --force.
#   git testing estado [<F>]
#       the sources and the commits made on TESTING, marked 'applied in <branch>' when already there.
#   git testing repartir [<F>] [--map <commit>=<branch>]... [--on-applied skip|apply]
#       commit by commit, a numbered menu (sources first, o = other branch, s = skip, q = quit) of
#       where to 'cherry-pick -x' each TESTING commit; --map gives the answers without questions.
#       A change already in the target is skipped (after asking). A failed cherry-pick leaves the
#       target untouched. Nothing is pushed.
# TESTING is never merged, rebased or integrated (hooks and 'git integra' refuse it): its "children" are
# the recorded sources. The guards live in git-flow-lib.sh; this file is also sourced for the release.

# shellcheck disable=SC1091
if ! declare -F is_testing_branch >/dev/null 2>&1; then
	. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-flow-lib.sh"
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

TST_SRC_BR=() TST_SRC_SHA=() TST_ORIG_SHA=""

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
tst_die() {
	echo "[testing] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
tst_say() { echo "[testing] $*"; }

# Level of the sandbox: the explicit one, or the level of the current branch.
# Arguments: $1 explicit level (may be empty). Returns: 0 and prints the level; 1 when the current
# branch has no level (develop, main, a detached HEAD).
tst_level() {
	local cur
	if [ -n "$1" ]; then
		printf '%s' "${1%/}"
		return 0
	fi
	cur="$(current_branch)" || return 1
	valid_branch_name "$cur" >/dev/null 2>&1 || return 1
	is_mainline "$cur" && return 1
	if is_testing_branch "$cur"; then
		printf '%s' "${cur%/*}"
	elif is_parent_branch "$cur"; then
		branch_node "$cur"
	else
		printf '%s' "${cur%/*}"
	fi
}

# The best ref of the sandbox of a level (local, or origin when it is ahead or only there).
# Arguments: $1 level. Returns: 0 and prints the ref; 1 when there is no such branch.
tst_ref() {
	best_ref "$1/$QS_BR_TESTING"
}

# The marker commit of a sandbox: the newest first-parent commit with a Testing-Create trailer.
# Arguments: $1 level. Returns: 0 and prints the sha; 1 when TESTING or the marker is missing.
tst_marker() {
	local ref m
	ref="$(tst_ref "$1")" || return 1
	m="$(git log --first-parent -n1 --format=%H --grep='^Testing-Create: ' "$ref" 2>/dev/null)"
	[ -n "$m" ] || return 1
	printf '%s' "$m"
}

# Read the sources and the ORIGINAL recorded in the marker commit into TST_SRC_BR, TST_SRC_SHA,
# TST_ORIG_SHA, and rebuild the git-config cache when it is missing or different.
# Arguments: $1 level. Returns: 0 on success; 1 when there is no readable marker.
tst_load() {
	local m body line cache want i
	TST_SRC_BR=() TST_SRC_SHA=() TST_ORIG_SHA=""
	m="$(tst_marker "$1")" || return 1
	body="$(git log -n1 --format=%B "$m")"
	while IFS= read -r line; do
		case "$line" in
		"Testing-Create: "*)
			read -r _ TST_ORIG_SHA <<<"${line#Testing-Create: }"
			;;
		esac
	done <<<"$body"
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		TST_SRC_BR+=("${line%% *}")
		TST_SRC_SHA+=("${line##* }")
	done < <(awk '/^Sources:$/ { on = 1; next } on && NF == 0 { exit } on { print }' <<<"$body")
	[ -n "$TST_ORIG_SHA" ] || return 1
	want=""
	for i in "${!TST_SRC_BR[@]}"; do want="$want${TST_SRC_BR[$i]} ${TST_SRC_SHA[$i]}"$'\n'; done
	cache="$(git config --get-all "qs.testing.$1.sources" 2>/dev/null || true)"$'\n'
	if [ "$cache" != "$want" ]; then
		git config --unset-all "qs.testing.$1.sources" 2>/dev/null || true
		for i in "${!TST_SRC_BR[@]}"; do
			git config --add "qs.testing.$1.sources" "${TST_SRC_BR[$i]} ${TST_SRC_SHA[$i]}"
		done
	fi
	return 0
}

# Whether the change of a commit is already in a branch: the same stable patch-id among the commits
# of the branch since its merge base with the sandbox, or its diff reverse-applies cleanly to the
# branch tree.
# Arguments: $1 commit, $2 ref of the target, $3 ref of the sandbox. Returns: 0 when present.
tst_applied_in() {
	local c="$1" ref="$2" tref="$3" base range pid idx rc
	pid="$(git diff "$c^" "$c" | git patch-id --stable | cut -d' ' -f1)"
	[ -n "$pid" ] || return 1 # an empty commit has no change to find
	base="$(git merge-base "$tref" "$ref" 2>/dev/null || true)"
	range="$ref"
	[ -z "$base" ] || range="$base..$ref"
	if git log -p --no-merges --format='commit %H' "$range" 2>/dev/null |
		git patch-id --stable | cut -d' ' -f1 | grep -qxF "$pid"; then
		return 0
	fi
	idx="$(mktemp)"
	rc=1
	if GIT_INDEX_FILE="$idx" git read-tree "$ref" 2>/dev/null &&
		git diff "$c^" "$c" | GIT_INDEX_FILE="$idx" git apply --cached --check -R 2>/dev/null; then
		rc=0
	fi
	rm -f "$idx"
	return "$rc"
}

# The commits made on TESTING, oldest first: non-merge commits not reachable from the ORIGINAL or
# the sources recorded at creation, and not the marker.
# Arguments: $1 level. Returns: 0 and prints one sha per line; 1 when there is no sandbox.
tst_commits() {
	local ref m i excl=()
	ref="$(tst_ref "$1")" || return 1
	tst_load "$1" || return 1
	m="$(tst_marker "$1")"
	excl=("^$TST_ORIG_SHA")
	for i in "${!TST_SRC_SHA[@]}"; do
		# why: a source never pushed is unknown in a fresh clone; it cannot hold commits we could see
		if git cat-file -e "${TST_SRC_SHA[$i]}^{commit}" 2>/dev/null; then excl+=("^${TST_SRC_SHA[$i]}"); fi
	done
	git rev-list --no-merges --reverse "$ref" "${excl[@]}" | grep -vxF "$m" || true
}

# The branches where the change of a commit already is: the sources (by change) and the targets
# recorded by 'repartir'. Needs tst_load first.
# Arguments: $1 level, $2 commit. Returns: 0; prints one branch per line (possibly none).
tst_applied_list() {
	local i b ref tref line
	tref="$(tst_ref "$1")"
	for i in "${!TST_SRC_BR[@]}"; do
		b="${TST_SRC_BR[$i]}"
		ref="$(best_ref "$b" || true)"
		[ -n "$ref" ] && tst_applied_in "$2" "$ref" "$tref" && echo "$b"
	done
	while IFS= read -r line; do
		[ "${line%% *}" = "$2" ] && echo "${line#* }"
	done < <(git config --get-all "qs.testing.$1.distributed" 2>/dev/null || true)
	return 0
}

# The commits of TESTING that are in no source and were not distributed.
# Arguments: $1 level. Returns: 0; prints one sha per line (possibly none).
tst_undistributed() {
	local c
	while IFS= read -r c; do
		[ -n "$c" ] || continue
		[ -z "$(tst_applied_list "$1" "$c")" ] && echo "$c"
	done < <(tst_commits "$1")
	return 0
}

# Release helper (see testing_release_ok in git-flow-lib.sh): is a sandbox free of undistributed
# commits? Warns on stderr, naming them, when it is not.
# Arguments: $1 level. Returns: 0 when nothing is left to distribute; 1 otherwise (also when the
# marker cannot be read, because then nothing can be proved).
tst_release_ok() {
	local pend c
	if ! tst_load "$1"; then
		echo "[rama] WARN: $1/$QS_BR_TESTING has no readable marker commit: set aside, not deleted" >&2
		return 1
	fi
	pend="$(tst_undistributed "$1")"
	[ -z "$pend" ] && return 0
	echo "[rama] WARN: $1/$QS_BR_TESTING has undistributed commits (git testing repartir):" >&2
	while IFS= read -r c; do
		[ -n "$c" ] && echo "         $(git log -n1 --format='%h %s' "$c")" >&2
	done <<<"$pend"
	return 1
}

# Find where a local branch is checked out.
# Arguments: $1 branch. Returns: 0 and prints the work tree path when checked out; 1 otherwise.
tst_worktree_of() {
	local out
	out="$(git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{w=substr($0,10)} $0 == "branch " b { print w; exit }')"
	[ -n "$out" ] || return 1
	printf '%s' "$out"
}

# Cherry-pick a commit (-x) onto a local branch inside a work tree, undoing everything on failure.
# Arguments: $1 commit, $2 branch. Returns: 0 applied; 1 failed (branch untouched); 2 the branch is
# checked out elsewhere with uncommitted changes (not touched; the path is in TST_BUSY).
tst_cherry_pick() {
	local c="$1" br="$2" wt tmp="" head rc=0
	TST_BUSY=""
	if wt="$(tst_worktree_of "$br")"; then
		if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no </dev/null)" ]; then
			TST_BUSY="$wt"
			return 2
		fi
	else
		git show-ref --verify -q "refs/heads/$br" || git branch -q --no-track "$br" "origin/$br"
		tmp="$(mktemp -d)"
		git worktree add -q "$tmp" "$br" </dev/null >/dev/null 2>&1 || {
			rm -rf "$tmp"
			return 1
		}
		wt="$tmp"
	fi
	head="$(git -C "$wt" rev-parse HEAD)"
	git -C "$wt" cherry-pick -x "$c" </dev/null >/dev/null 2>&1 || rc=1
	if [ "$rc" = 1 ]; then
		git -C "$wt" cherry-pick --abort </dev/null >/dev/null 2>&1 || true
		git -C "$wt" reset -q --hard "$head" </dev/null >/dev/null 2>&1 || true
	fi
	if [ -n "$tmp" ]; then
		git worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
		git worktree prune >/dev/null 2>&1 || true
	fi
	return "$rc"
}

# Build the sandbox of a level with plumbing: merge each source, then the marker commit.
# Arguments: $1 level, $2.. source branch names. Prints the new tip sha on stdout. Returns: 0 on
# success; 1 (message on stderr, nothing changed) on a missing branch or a conflict.
tst_build() {
	local f="$1" orig_ref acc sha ref src tree out rc j other msgf marker
	shift
	local names=() shas=()
	orig_ref="$(best_ref "$f/$QS_BR_LEAF" || true)"
	[ -n "$orig_ref" ] || {
		echo "[testing] '$f/$QS_BR_LEAF' does not exist" >&2
		return 1
	}
	TST_ORIG_SHA="$(git rev-parse "$orig_ref^{commit}")"
	acc="$TST_ORIG_SHA"
	for src in "$@"; do
		is_testing_branch "$src" && {
			echo "[testing] '$src' is a TESTING sandbox: it cannot be a source" >&2
			return 1
		}
		ref="$(best_ref "$src" || true)"
		[ -n "$ref" ] || {
			echo "[testing] source '$src' does not exist" >&2
			return 1
		}
		sha="$(git rev-parse "$ref^{commit}")"
		rc=0
		out="$(git merge-tree --write-tree "$acc" "$sha" 2>&1)" || rc=$?
		if [ "$rc" != 0 ]; then
			other="$f/$QS_BR_LEAF or the sources before it"
			for j in "${!names[@]}"; do
				git merge-tree --write-tree "${shas[$j]}" "$sha" >/dev/null 2>&1 && continue
				other="${names[$j]}"
				break
			done
			echo "[testing] '$src' conflicts with '$other': nothing was created. Choose sources that do not overlap." >&2
			return 1
		fi
		tree="$(head -n1 <<<"$out")"
		acc="$(git commit-tree "$tree" -p "$acc" -p "$sha" -m "Merge branch '$src' into $f/$QS_BR_TESTING")"
		names+=("$src")
		shas+=("$sha")
	done
	msgf="$(mktemp)"
	{
		printf 'chore(testing): create\n\nSources:\n'
		for j in "${!names[@]}"; do printf '%s %s\n' "${names[$j]}" "${shas[$j]}"; done
		printf '\nTesting-Create: %s %s\n' "$f/$QS_BR_LEAF" "$TST_ORIG_SHA"
	} >"$msgf"
	marker="$(git commit-tree "$(git rev-parse "$acc^{tree}")" -p "$acc" -F "$msgf")"
	rm -f "$msgf"
	printf '%s' "$marker"
}

# git testing crear: create (or re-create) the sandbox.
# Arguments: the command line after 'crear'. Returns: 0 on success; exits 1 on any error.
cmd_crear() {
	local level="" recrear=0 force=0 srcs=() f tref tip old pend c i
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--nivel)
			[ "$#" -ge 2 ] || tst_die "--nivel needs a level"
			level="$2"
			shift
			;;
		--recrear) recrear=1 ;;
		--force) force=1 ;;
		-*) tst_die "unknown option $1" ;;
		*) srcs+=("$1") ;;
		esac
		shift
	done
	f="$(tst_level "$level")" || tst_die "no level: use --nivel <F> (e.g. --nivel 5.0.0-RC1/git)"
	tref="$f/$QS_BR_TESTING"
	git fetch -q --prune origin 2>/dev/null || true
	if best_ref "$tref" >/dev/null; then
		[ "$recrear" = 1 ] || tst_die "$tref already exists: git testing crear --recrear (or git testing estado)"
		if [ "${#srcs[@]}" -eq 0 ] && tst_load "$f"; then srcs=("${TST_SRC_BR[@]}"); fi
		if [ "$force" != 1 ]; then
			pend="$(tst_undistributed "$f")"
			if [ -n "$pend" ]; then
				echo "[testing] $tref has commits not distributed yet (git testing repartir, or --force):" >&2
				while IFS= read -r c; do echo "  $(git log -n1 --format='%h %s' "$c")" >&2; done <<<"$pend"
				exit 1
			fi
		else
			# why: --force destroys the undistributed commits; say which ones and how to get them back
			pend="$(tst_undistributed "$f" 2>/dev/null || true)"
			tip="$(git rev-parse "$(tst_ref "$f")")"
			if [ -n "$pend" ]; then
				echo "[testing] --force: dropping undistributed commits of $tref (old tip $tip):" >&2
				while IFS= read -r c; do echo "  $(git log -n1 --format='%h %s' "$c")" >&2; done <<<"$pend"
				echo "[testing] recover them with: git branch <name> $tip   (or git reflog show $tref)" >&2
			fi
		fi
		tst_worktree_of "$tref" >/dev/null && tst_die "$tref is checked out: switch to another branch first"
	fi
	[ "${#srcs[@]}" -gt 0 ] || tst_die "usage: git testing crear <branch...> [--nivel <F>] [--recrear [--force]]"
	tip="$(tst_build "$f" "${srcs[@]}")" || exit 1
	old="$(git rev-parse -q --verify "refs/heads/$tref" 2>/dev/null || echo 0000000000000000000000000000000000000000)"
	git update-ref -m "testing: create" "refs/heads/$tref" "$tip" "$old"
	git config --unset-all "qs.testing.$f.distributed" 2>/dev/null || true
	tst_load "$f" || tst_die "internal error: the marker of $tref cannot be read"
	tst_say "created $tref from $f/$QS_BR_LEAF with ${#srcs[@]} source(s):"
	for i in "${!TST_SRC_BR[@]}"; do echo "  ${TST_SRC_BR[$i]} ${TST_SRC_SHA[$i]:0:10}"; done
	echo "Make commits on $tref; share it with: git push --force-with-lease origin $tref"
}

# git testing estado: show the sources and the commits made on TESTING.
# Arguments: [<level>]. Returns: 0; exits 1 when there is no sandbox.
cmd_estado() {
	local level="${1:-}" f tref i n c apps b ref
	f="$(tst_level "$level")" || tst_die "no level: pass it (git testing estado <F>)"
	tref="$f/$QS_BR_TESTING"
	tst_load "$f" || tst_die "no TESTING sandbox at $f (git testing crear <branch...>)"
	echo "$tref  (created from $f/$QS_BR_LEAF ${TST_ORIG_SHA:0:10})"
	echo "Sources:"
	for i in "${!TST_SRC_BR[@]}"; do
		b="${TST_SRC_BR[$i]}"
		ref="$(best_ref "$b" || true)"
		n=0
		[ -n "$ref" ] && n="$(git rev-list --count "${TST_SRC_SHA[$i]}..$ref" 2>/dev/null || echo 0)"
		echo "  $b ${TST_SRC_SHA[$i]:0:10}$([ "$n" -gt 0 ] && echo "  ($n new commits since)")"
	done
	echo "Commits on TESTING:"
	n=0
	while IFS= read -r c; do
		[ -n "$c" ] || continue
		n=$((n + 1))
		apps="$(tst_applied_list "$f" "$c" | sort -u | paste -sd, - | sed 's/,/, /g')"
		echo "  $(git log -n1 --format='%h %s' "$c")${apps:+  [applied in $apps]}"
	done < <(tst_commits "$f")
	[ "$n" -gt 0 ] || echo "  (none)"
	return 0
}

# Ask a yes/no question on stdin, default yes; end of input means yes.
# Arguments: $1 question. Returns: 0 for yes, 1 for no.
tst_ask_yes() {
	local a
	printf '%s [Y/n] ' "$1" >&2
	read -r a || a=""
	case "$a" in n | N | no | NO) return 1 ;; esac
	return 0
}

# Numbered menu for one commit; the answer is left in TST_CHOICE (a branch name).
# Arguments: $1 commit. Returns: 0 a branch was chosen; 1 skip; 2 quit (also at end of input).
tst_menu() {
	local c="$1" i n ans b
	n="${#TST_SRC_BR[@]}"
	while :; do
		echo "commit $(git log -n1 --format='%h %s' "$c")" >&2
		for i in "${!TST_SRC_BR[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${TST_SRC_BR[$i]}" >&2; done
		echo "  o) other branch   s) skip   q) quit" >&2
		printf 'choice: ' >&2
		read -r ans || return 2
		case "$ans" in
		s | S) return 1 ;;
		q | Q) return 2 ;;
		o | O)
			while :; do
				printf 'branch: ' >&2
				read -r b || return 2
				[ -n "$b" ] || break
				if best_ref "$b" >/dev/null; then
					TST_CHOICE="$b"
					return 0
				fi
				echo "unknown branch '$b'" >&2
			done
			;;
		*[!0-9]* | '') echo "not an option: '$ans'" >&2 ;;
		*)
			if [ "$ans" -ge 1 ] && [ "$ans" -le "$n" ]; then
				TST_CHOICE="${TST_SRC_BR[$((ans - 1))]}"
				return 0
			fi
			echo "not an option: '$ans'" >&2
			;;
		esac
	done
}

# git testing repartir: move the TESTING commits to branches with cherry-pick -x.
# Arguments: [<level>] [--map <commit>=<branch>]... [--on-applied skip|apply]. Returns: 0 when
# nothing failed; 1 when a cherry-pick failed; exits 1 on a usage error.
cmd_repartir() {
	local level="" on_applied=skip maps=() mapped=0 m c br sha targets t rc ref tref f
	local res=() fails=0 quit=0 line short subj
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--map)
			[ "$#" -ge 2 ] || tst_die "--map needs <commit>=<branch>"
			maps+=("$2")
			mapped=1
			shift
			;;
		--on-applied)
			[ "$#" -ge 2 ] || tst_die "--on-applied needs skip or apply"
			on_applied="$2"
			shift
			;;
		-*) tst_die "unknown option $1" ;;
		*) level="$1" ;;
		esac
		shift
	done
	case "$on_applied" in skip | apply) ;; *) tst_die "--on-applied is skip or apply" ;; esac
	f="$(tst_level "$level")" || tst_die "no level: pass it (git testing repartir <F>)"
	tref="$(tst_ref "$f")" || tst_die "no TESTING sandbox at $f"
	tst_load "$f" || tst_die "the marker of $tref cannot be read"
	local commits=() resolved=()
	while IFS= read -r c; do [ -n "$c" ] && commits+=("$c"); done < <(tst_commits "$f")
	[ "${#commits[@]}" -gt 0 ] || {
		tst_say "nothing to distribute: no commits were made on $tref"
		return 0
	}
	for m in ${maps[@]+"${maps[@]}"}; do
		sha="$(git rev-parse -q --verify "${m%%=*}^{commit}" 2>/dev/null)" || tst_die "--map: unknown commit '${m%%=*}'"
		printf '%s\n' "${commits[@]}" | grep -qxF "$sha" || tst_die "--map: ${m%%=*} is not a commit made on $tref"
		br="${m#*=}"
		if [ "$br" = "$m" ] || ! best_ref "$br" >/dev/null; then tst_die "--map: unknown branch '$br'"; fi
		resolved+=("$sha $br")
	done
	for c in "${commits[@]}"; do
		short="$(git log -n1 --format='%h' "$c")"
		subj="$(git log -n1 --format='%s' "$c")"
		targets=""
		if [ "$quit" = 1 ]; then
			res+=("$short $subj: not asked (quit)")
			continue
		fi
		if [ "$mapped" = 1 ]; then
			for line in ${resolved[@]+"${resolved[@]}"}; do
				[ "${line%% *}" = "$c" ] && targets="$targets ${line#* }"
			done
			if [ -z "$targets" ]; then
				res+=("$short $subj: skipped (not mapped)")
				continue
			fi
		else
			rc=0
			tst_menu "$c" || rc=$?
			if [ "$rc" = 1 ]; then
				res+=("$short $subj: skipped")
				continue
			elif [ "$rc" = 2 ]; then
				quit=1
				res+=("$short $subj: not asked (quit)")
				continue
			fi
			targets="$TST_CHOICE"
		fi
		for t in $targets; do
			ref="$(best_ref "$t")"
			if tst_applied_in "$c" "$ref" "$tref"; then
				if [ "$mapped" = 1 ]; then
					[ "$on_applied" = skip ] && rc=0 || rc=1
				else
					tst_ask_yes "already in $t: skip?" && rc=0 || rc=1
				fi
				if [ "$rc" = 0 ]; then
					res+=("$short $subj: already present in $t")
					git config --add "qs.testing.$f.distributed" "$c $t"
					continue
				fi
			fi
			rc=0
			tst_cherry_pick "$c" "$t" || rc=$?
			case "$rc" in
			0)
				res+=("$short $subj: applied to $t")
				git config --add "qs.testing.$f.distributed" "$c $t"
				;;
			2) res+=("$short $subj: skipped, $t is checked out with changes in $TST_BUSY") ;;
			*)
				res+=("$short $subj: failed in $t (conflict or rejected; $t untouched)")
				fails=$((fails + 1))
				;;
			esac
		done
	done
	echo "Summary:"
	for line in "${res[@]}"; do echo "  $line"; done
	[ "$fails" = 0 ]
}

# Entry point of the git alias.
# Arguments: the command line after 'git testing'. Returns: the exit status of the command.
tst_main() {
	local cmd="${1:-}"
	shift || true
	qs_policy_load
	case "$cmd" in
	crear | create) cmd_crear "$@" ;;
	estado | status) cmd_estado "$@" ;;
	repartir | distribute) cmd_repartir "$@" ;;
	*)
		awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
		exit 2
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then tst_main "$@"; fi
