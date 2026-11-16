#!/usr/bin/env bash
# git-intentos.sh (git aliases: git intentos, git elegir) - ATTEMPT branches: N tries of one task.
# qs-alias: intentos elegir
#   git intentos <task> <N> [--yes]
#       '<task>' (a final branch, '<v>/<ot>/a') becomes the parent '<task>/ORIGINAL' (renamed, also on
#       origin) and gets N attempts '<task>/ATTEMPT-1..N' created from it, each in its own worktree
#       (next to the checkout, in '<checkout>.attempts/'). --yes: no question before renaming a
#       branch that is on origin.
#   git elegir <task>
#       compares the attempts (gate findings, tests, diff size), prints a table and a proposal and
#       WAITS for a person: a number chooses that attempt, 'y' the proposal, anything else (or no
#       answer) changes nothing. The chosen attempt lands on '<task>/ORIGINAL' as ONE squash commit
#       (Commits:, Files:, Norms:, Refs:, Squashed: and 'Chosen-from: ATTEMPT-<n>', the comparison in
#       the body); then every attempt and its worktree is deleted and the tips are printed.
#       --auto does not exist (decision 9: a person always confirms).
# why one script, two aliases: the alias line cannot tell the script which name was used, so the
# arguments decide: '<task> <N>' creates, a task that already has attempts is chosen.
# Nothing here pushes an ORIGINAL: the squash lands locally and the push command is printed.

# shellcheck disable=SC1091
if ! declare -F valid_branch_name >/dev/null 2>&1; then
	. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-flow-lib.sh"
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi
ATT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATT_SUITE="$(cd "$ATT_DIR/.." && pwd)"
ATT_YES=0

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
att_die() {
	echo "[intentos] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
att_say() { echo "[intentos] $*"; }

# Whether a ref exists.
# Arguments: $1 full ref name. Returns: 0 when it does, 1 otherwise.
att_ref() { git rev-parse -q --verify "$1" >/dev/null 2>&1; }

# Whether a branch exists locally or on origin.
# Arguments: $1 branch. Returns: 0 when it does, 1 otherwise.
att_exists() { att_ref "refs/heads/$1" || att_ref "refs/remotes/origin/$1"; }

# The full ref of a branch: the local one, or the one on origin when only that exists.
# Arguments: $1 branch. Returns: 0; prints the full ref name.
att_best() {
	if att_ref "refs/heads/$1"; then printf 'refs/heads/%s' "$1"; else printf 'refs/remotes/origin/%s' "$1"; fi
}

# Whether an origin remote is configured.
# Arguments: none. Returns: 0 when it is, 1 otherwise.
att_has_origin() { git remote get-url origin >/dev/null 2>&1; }

# Fetch origin quietly (nothing happens without origin or when offline).
# Arguments: none. Returns: 0.
att_fetch() {
	att_has_origin && git fetch -q --prune origin 2>/dev/null || true
	return 0
}

# Ask a yes/no question on the terminal ('--yes' answers yes).
# Arguments: $1 question. Returns: 0 on yes; 1 on no or without a terminal.
att_confirm() {
	local r
	[ "$ATT_YES" = 1 ] && return 0
	printf '%s [y/N] ' "$1" >/dev/tty 2>/dev/null || return 1
	read -r r </dev/tty || r=""
	case "$r" in y | Y | s | S | yes | si) return 0 ;; esac
	return 1
}

# Check that ATTEMPT branches are possible here (squash flow, type enabled).
# Arguments: none. Returns: 0; exits through att_die otherwise.
att_require_enabled() {
	special_enabled ATTEMPT ||
		att_die "ATTEMPT branches need branches.flow = squash and the ATTEMPT type enabled in branches.special"
}

# The worktree directory of a branch, when it is checked out in one.
# Arguments: $1 branch. Returns: 0 and prints the path; 1 when no worktree has it.
att_worktree_of() {
	local p
	p="$(git worktree list --porcelain | awk -v b="branch refs/heads/$1" '
		$1 == "worktree" { sub(/^worktree /, ""); w = $0 }
		$0 == b { print w; exit }')"
	[ -n "$p" ] || return 1
	printf '%s' "$p"
}

# The attempt branches of a task, local or on origin, ordered by number.
# Arguments: $1 task. Returns: 0; prints "<n> <branch>" lines ('<task>/ATTEMPT-<n>' or the parent
# '<task>/ATTEMPT-<n>/ORIGINAL' of an attempt that has children), nothing when there are none.
att_list() {
	local t="$1"
	{
		git for-each-ref --format='%(refname:lstrip=2)' "refs/heads/$t/"
		git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/$t/"
	} | awk -v t="$t/" -v leaf="$QS_BR_LEAF" '
		index($0, t) == 1 {
			r = substr($0, length(t) + 1)
			if (match(r, /^ATTEMPT-[0-9]+$/)) { n = substr(r, 9); print n + 0, $0 }
			else if (match(r, /^ATTEMPT-[0-9]+\//)) {
				split(r, p, "/")
				if (p[2] == leaf && p[3] == "") { n = substr(p[1], 9); print n + 0, $0 }
			}
		}' | sort -u -n
}

# The branches below an attempt that has become a parent (its pending children).
# Arguments: $1 attempt folder ('<task>/ATTEMPT-<n>'). Returns: 0; prints one branch per line.
att_pending() {
	local f="$1"
	{
		git for-each-ref --format='%(refname:lstrip=2)' "refs/heads/$f/"
		git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/$f/"
	} | grep -v -x -F "$f/$QS_BR_LEAF" | sort -u || true
}

# Publish a created branch through the suite when the autopublish helper is available.
# Arguments: $1 branch. Returns: 0 (a missing helper or a failed push is not an error here).
att_publish() {
	command -v qs_publish_new >/dev/null 2>&1 && qs_publish_new "$1" || true
	return 0
}

# ---- git intentos -------------------------------------------------------------------------------

# Create the structure of a task with attempts.
# Arguments: $1 task branch, $2 number of attempts (1-20). Returns: 0; exits through att_die and
# changes nothing when the task or a target name is not valid.
cmd_intentos() {
	local task="$1" n="$2" why i orig base top apath on_origin=0 paths=() names=()
	att_require_enabled
	printf '%s' "$n" | grep -qE '^[1-9][0-9]?$' && [ "$n" -le 20 ] || att_die "N is a number from 1 to 20: '$n'"
	att_fetch
	why="$(valid_branch_name "$task")" || att_die "invalid branch '$task': $why"
	is_mainline "$task" && att_die "'$task' is a mainline branch"
	is_parent_branch "$task" && att_die "'$task' is a parent branch: attempts are made of a final task branch"
	[ -z "$(special_kind "$task")" ] || att_die "'$task' is a special branch: attempts are made of an ordinary task"
	att_exists "$task" || att_die "branch '$task' not found"
	orig="$task/$QS_BR_LEAF"
	att_exists "$orig" && att_die "'$task' already has a '$orig'"
	[ -z "$(att_list "$task")" ] || att_die "'$task' already has attempts"
	top="$(git rev-parse --show-toplevel)"
	for ((i = 1; i <= n; i++)); do
		names+=("$task/ATTEMPT-$i")
		why="$(valid_branch_name "$task/ATTEMPT-$i")" || att_die "invalid name '$task/ATTEMPT-$i': $why"
		att_exists "$task/ATTEMPT-$i" && att_die "'$task/ATTEMPT-$i' already exists"
		apath="$top.attempts/$(printf '%s' "$task/ATTEMPT-$i" | tr '/' '-')"
		[ ! -e "$apath" ] || att_die "'$apath' already exists: remove it first"
		paths+=("$apath")
	done
	att_ref "refs/remotes/origin/$task" && on_origin=1
	if [ "$on_origin" = 1 ]; then
		att_say "'$task' is on origin: converting it deletes origin/$task and publishes '$orig'."
		att_confirm "Continue?" || att_die "cancelled; nothing was changed"
	fi
	att_ref "refs/heads/$task" || git branch -q --no-track "$task" "origin/$task"
	git branch -q -m "$task" "$orig" || att_die "cannot rename '$task' to '$orig'"
	if [ "$on_origin" = 1 ]; then
		git push -q origin --delete "$task" || att_say "WARN: could not delete origin/$task"
		git push -q -u origin "$orig" || att_say "WARN: could not publish '$orig': git subir"
	else
		att_publish "$orig"
	fi
	base="$orig"
	mkdir -p "$top.attempts"
	for ((i = 0; i < n; i++)); do
		git worktree add -q -b "${names[$i]}" "${paths[$i]}" "$base" ||
			att_die "cannot create '${names[$i]}' in '${paths[$i]}' (created so far: ${names[*]:0:i})"
		att_publish "${names[$i]}"
		att_say "${names[$i]} -> ${paths[$i]}"
	done
	att_say "'$task' is now '$orig' with $n attempts. Compare and choose: git elegir $task"
}

# ---- git elegir ---------------------------------------------------------------------------------

# Measure one attempt in a throwaway worktree of its tip: gate findings on the files it changed,
# the project tests, and the diff size against the base.
# Arguments: $1 attempt ref, $2 base ref. Returns: 0; prints "<findings>|<tests>|<added>|<deleted>"
# where findings is a number or '?' (the gate could not run) and tests is pass, FAIL or none.
att_metrics() {
	local ref="$1" base="$2" tmp w files out rc findings tests total added deleted
	tmp="$(mktemp -d "$(git rev-parse --absolute-git-dir)/quality-suite/attempt-XXXXXX" 2>/dev/null)" || {
		mkdir -p "$(git rev-parse --absolute-git-dir)/quality-suite"
		tmp="$(mktemp -d "$(git rev-parse --absolute-git-dir)/quality-suite/attempt-XXXXXX")" || return 1
	}
	w="$tmp/w"
	findings='?' tests=none
	if git worktree add -q --detach "$w" "$ref" >/dev/null 2>&1; then
		mapfile -t files < <(git diff --name-only --diff-filter=ACMR "$base" "$ref")
		if [ "${#files[@]}" -eq 0 ]; then
			findings=0
		else
			rc=0
			out="$(cd "$w" && bash "$ATT_SUITE/scripts/qs-run.sh" --check "${files[@]}" 2>&1)" || rc=$?
			findings="$(printf '%s\n' "$out" | grep -cE '^\[qs:[^]]*\] [^ ]+:[0-9]+' || true)"
			[ "$rc" -eq 0 ] || [ "$findings" -gt 0 ] || findings='?'
		fi
		rc=0
		out="$(cd "$w" && QUALITY_SUITE_DIR="${QUALITY_SUITE_DIR:-$ATT_SUITE}" bash "$ATT_SUITE/scripts/run-tests.sh" "$w" 2>&1 </dev/null)" || rc=$?
		total="$(printf '%s\n' "$out" | grep -E '^\[quality-suite\] tests: ' | grep -vc 'none defined' || true)"
		if [ "$rc" -ne 0 ]; then
			tests=FAIL
		elif [ "${total:-0}" -gt 0 ]; then tests=pass; fi
		git worktree remove --force "$w" >/dev/null 2>&1 || true
	fi
	rm -rf "$tmp"
	read -r added deleted < <(git diff --numstat "$base" "$ref" | awk '$1 != "-" { a += $1; d += $2 } END { print a + 0, d + 0 }')
	printf '%s|%s|%s|%s' "$findings" "$tests" "$added" "$deleted"
}

# The proposal: the attempt with passing (or no) tests, then fewest gate findings, then the
# smallest diff, then the lowest number.
# Arguments: stdin lines "<n>|<findings>|<tests>|<added>|<deleted>". Returns: 0; prints the number.
att_propose() {
	awk -F'|' '{
		fail = ($3 == "FAIL") ? 1 : 0
		f = ($2 == "?") ? 999999 : $2
		printf "%d %d %d %d %d\n", fail, f, $4 + $5, $1, $1
	}' | sort -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n1 | awk '{ print $4 }'
}

# The union of the 'Norms:' ids of the commits base..rev, comma separated ('none' when none).
# Arguments: $1 base, $2 rev. Returns: 0; prints the ids.
att_norms() {
	git log --no-merges --format=%B "$1..$2" | sed -n 's/^Norms:[[:space:]]*//p' | tr -s ', \t' '\n' | awk '
		$0 == "" { next }
		tolower($0) == "none" { none = 1; next }
		!seen[$0]++ { out = out (out == "" ? "" : ", ") $0 }
		END { if (out != "") print out; else print "none" }'
}

# The Commits: block of base..rev, oldest first, merges left out.
# Arguments: $1 base, $2 rev. Returns: 0.
att_commits_block() {
	echo "Commits:"
	git log --reverse --no-merges --format='- %h %s' "$1..$2"
}

# The Files: block of base..rev (the library renderer when loaded, the same format otherwise).
# Arguments: $1 base, $2 rev. Returns: 0.
att_files_block() {
	local out
	if [ -f "$ATT_DIR/commit-files-lib.sh" ]; then
		# shellcheck disable=SC1091
		. "$ATT_DIR/commit-files-lib.sh"
		qs_files_block "$1" "$2"
		return 0
	fi
	echo "Files:"
	out="$(git -c core.quotePath=true diff --name-status -M "$1" "$2" || true)"
	[ -n "$out" ] && printf '%s\n' "$out" | tr '\t' ' ' || echo "(none)"
}

# Write the squash commit message of the chosen attempt.
# Arguments: $1 chosen number, $2 chosen ref, $3 base ref, $4 task, $5 subject (may be empty),
# $6 file with the comparison table lines, $7 output file. Returns: 0.
att_compose() {
	local n="$1" ref="$2" base="$3" task="$4" subject="$5" cmp="$6" out="$7" leaf
	leaf="${task##*/}"
	[ -n "$subject" ] || subject="$(printf 'feat(%s): attempt %s' "$leaf" "$n" | cut -c1-50)"
	{
		printf '%s\n\n' "$subject"
		printf 'Attempt %s of %s chosen. Comparison (gate findings, tests, diff):\n\n' "$n" "$task"
		cat "$cmp"
		echo
		att_commits_block "$base" "$ref"
		att_files_block "$base" "$ref"
		echo
		echo "Norms: $(att_norms "$base" "$ref")"
		echo "Refs: $ref -> $task/$QS_BR_LEAF"
		echo "Squashed: $ref $(git rev-parse "$ref^{commit}")"
		echo "Chosen-from: ATTEMPT-$n"
	} >"$out"
}

# Delete every attempt of a task: worktrees, local branches and origin copies; print the tips.
# Arguments: $1 task. Returns: 0; reports what it could not remove (locked files on Windows).
att_cleanup() {
	local task="$1" n b w tip left=()
	while read -r n b; do
		[ -n "$b" ] || continue
		tip="$(git rev-parse -q --verify "refs/heads/$b" 2>/dev/null || git rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null || true)"
		if w="$(att_worktree_of "$b")"; then
			git worktree remove --force "$w" >/dev/null 2>&1 || att_say "WARN: could not remove the worktree '$w' (locked?)"
		fi
		if att_ref "refs/heads/$b" && ! git branch -q -D "$b" >/dev/null 2>&1; then
			left+=("$b")
			att_say "WARN: could not delete '$b'"
		fi
		if att_ref "refs/remotes/origin/$b"; then
			git push -q origin --delete "$b" >/dev/null 2>&1 || att_say "WARN: could not delete origin/$b"
		fi
		att_say "deleted ATTEMPT-$n '$b' (tip ${tip:-unknown}; restore: git branch $b ${tip:-<sha>})"
	done < <(att_list "$task")
	git worktree prune >/dev/null 2>&1 || true
	[ "${#left[@]}" -eq 0 ] || att_say "kept (delete by hand): ${left[*]}"
	return 0
}

# Compare the attempts of a task, ask a person, and squash the chosen one into '<task>/ORIGINAL'.
# Arguments: $1 task or attempt branch, $2 optional commit subject. Returns: 0; exits through
# att_die (nothing changed) when refused, when the person does not confirm, or on a failure.
cmd_elegir() {
	local arg="$1" subject="${2:-}" task orig n b ref base rows="" row cmp tpl proposal ans chosen cref cur
	local pending new old top w
	att_require_enabled
	att_fetch
	if [[ $arg =~ ^(.+)/ATTEMPT-([0-9]+)(/ORIGINAL)?$ ]]; then
		task="${BASH_REMATCH[1]}"
		pending="$(att_pending "$task/ATTEMPT-${BASH_REMATCH[2]}")"
		[ -z "$pending" ] || att_die "ATTEMPT-${BASH_REMATCH[2]} has children pending: $(tr '\n' ' ' <<<"$pending")(integrate or delete them first, then: git elegir $task)"
		att_die "'$arg' is one attempt: name the task, git elegir $task"
	fi
	task="${arg%/"$QS_BR_LEAF"}"
	orig="$task/$QS_BR_LEAF"
	att_exists "$orig" || att_die "'$orig' not found: '$task' has no attempts (git intentos $task <N>)"
	[ -n "$(att_list "$task")" ] || att_die "'$task' has no attempts (git intentos $task <N>)"
	while read -r n b; do
		[ "$b" != "${b%/"$QS_BR_LEAF"}" ] || continue
		pending="$(att_pending "${b%/"$QS_BR_LEAF"}")"
		[ -z "$pending" ] || att_die "ATTEMPT-$n has children pending: $(tr '\n' ' ' <<<"$pending")(integrate or delete them first)"
	done < <(att_list "$task")
	cur="$(current_branch || true)"
	case "$cur" in "$task"/ATTEMPT-*) att_die "you are on '$cur': switch to another branch first" ;; esac
	att_ref "refs/heads/$orig" || git branch -q --no-track "$orig" "origin/$orig"
	if att_ref "refs/remotes/origin/$orig" && ! git merge-base --is-ancestor "refs/remotes/origin/$orig" "refs/heads/$orig"; then
		att_die "'$orig' is behind or differs from origin: git subir"
	fi
	base="refs/heads/$orig"
	cmp="$(mktemp)" tpl="$(mktemp)" ATT_CMP="$cmp" ATT_TPL="$tpl"
	trap 'rm -f "${ATT_CMP:-}" "${ATT_TPL:-}"' EXIT
	att_say "measuring the attempts of '$task' (gate, tests, diff)..."
	while read -r n b; do
		ref="$(att_best "$b")"
		row="$(att_metrics "$ref" "$base")"
		rows="$rows$n|$row"$'\n'
	done < <(att_list "$task")
	printf '%-10s %-14s %-8s %s\n' attempt gate-findings tests diff
	while IFS='|' read -r n f t a d; do
		[ -n "$n" ] || continue
		printf '%-10s %-14s %-8s +%s/-%s\n' "ATTEMPT-$n" "$f" "$t" "$a" "$d"
		printf -- '- ATTEMPT-%s: gate findings %s, tests %s, diff +%s/-%s\n' "$n" "$f" "$t" "$a" "$d" >>"$cmp"
	done <<<"$rows"
	proposal="$(printf '%s' "$rows" | att_propose)"
	echo "Proposal: ATTEMPT-$proposal (tests not failing, fewest findings, smallest diff)"
	printf 'Choose the attempt number, y = the proposal, anything else = change nothing: '
	read -r ans || ans=""
	case "$ans" in y | Y | s | S | yes | si) chosen="$proposal" ;; *) chosen="$ans" ;; esac
	if ! printf '%s' "$chosen" | grep -qE '^[0-9]+$' || ! printf '%s' "$rows" | grep -q "^$chosen|"; then
		att_say "nothing chosen; nothing was changed"
		exit 1
	fi
	while read -r n b; do
		[ "$n" = "$chosen" ] || continue
		cref="$(att_best "$b")"
		chosen="$b"
	done < <(att_list "$task")
	git merge-base --is-ancestor "$base" "$cref" || att_die "'$chosen' does not contain '$orig' (it moved): git subir in that attempt, then git elegir $task"
	[ -n "$(git rev-list -n1 "$base..$cref")" ] || att_die "'$chosen' has nothing that '$orig' lacks"
	if w="$(att_worktree_of "$orig")"; then
		top="$(git rev-parse --show-toplevel)"
		[ "$w" = "$top" ] || att_die "'$orig' is checked out in another worktree ($w): free it there first (git switch -)"
		[ -z "$(git status --porcelain)" ] || att_die "the work tree has changes: commit or stash them first"
	fi
	if [ -n "$subject" ]; then
		LC_ALL=C grep -q '[^ -~]' <<<"$subject" && att_die "the subject must be ASCII"
		[ "${#subject}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || att_die "the subject is longer than ${QS_COMMIT_SUBJECT_MAX:-50} characters"
	fi
	att_compose "${chosen##*ATTEMPT-}" "$cref" "$base" "$task" "$subject" "$cmp" "$tpl"
	old="$(git rev-parse "$base")"
	new="$(git commit-tree "$(git rev-parse "$cref^{tree}")" -p "$old" -F "$tpl")" || att_die "cannot create the squash commit"
	git update-ref -m "elegir: $chosen" "$base" "$new" "$old" || att_die "cannot move '$orig'"
	if att_worktree_of "$orig" >/dev/null; then git reset -q --hard "$new"; fi
	att_say "'$chosen' -> '$orig' (squash) as $(git rev-parse --short "$new")"
	att_cleanup "$task"
	att_say "done. Push: git push origin $orig   (then git integra from '$orig' when the work is complete)"
}

# Entry point: decide between the two commands from the arguments.
# Arguments: the command line. Returns: 0; exits through att_die on a usage error.
att_main() {
	local args=() subject="" a
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--auto | --auto=*) att_die "--auto does not exist: choosing an attempt always needs a person to confirm" ;;
		--yes | -y) ATT_YES=1 ;;
		-m)
			[ "$#" -ge 2 ] || att_die "-m needs a subject"
			subject="$2"
			shift
			;;
		-*) att_die "unknown option '$1'" ;;
		*) args+=("$1") ;;
		esac
		shift
	done
	qs_policy_load
	a="${args[0]:-}"
	[ -n "$a" ] || att_die "usage: git intentos <task> <N>   |   git elegir <task>"
	if [ "${#args[@]}" -ge 2 ]; then
		[ "${#args[@]}" -eq 2 ] || att_die "too many arguments"
		cmd_intentos "$a" "${args[1]}"
	elif [ -n "$(att_list "${a%/"$QS_BR_LEAF"}")" ] || [[ $a =~ /ATTEMPT-[0-9]+(/ORIGINAL)?$ ]]; then
		cmd_elegir "$a" "$subject"
	else
		att_die "usage: git intentos <task> <N>   |   git elegir <task>   ('$a' has no attempts yet)"
	fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then att_main "$@"; fi
