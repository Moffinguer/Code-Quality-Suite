#!/usr/bin/env bash
# commit-files-lib.sh - the "Files:" block of every commit message (5.0.0-RC1).
# Sourced by hooks/prepare-commit-msg and hooks/commit-msg (and by git integra). Policy:
# commit.files in .quality-rules.json (QS_COMMIT_FILES): block (default), warn, off.
# Layout: the block goes before the trailer paragraph (Norms:, Refs:, ...), so
# `git interpret-trailers` and %(trailers) still parse the trailers.

# qs_empty_tree: print the id of the empty tree (base of a root commit).
qs_empty_tree() {
	git hash-object -t tree /dev/null
}

# qs_comment_char: print the comment character git uses in commit messages ('#' when auto).
qs_comment_char() {
	local cc
	cc="$(git config core.commentChar 2>/dev/null || echo '#')"
	{ [ -n "$cc" ] && [ "$cc" != auto ]; } || cc='#'
	printf '%s\n' "$cc"
}

# qs_files_block BASE [REV]: print the "Files:" block, one "<status> <path>" line per file
# (renames as "R <old> -> <new>"), or "(none)" when nothing changed. Without REV it compares
# the index with BASE; with REV it compares BASE with REV. Paths come from core.quotePath=true,
# so non-ASCII names are ASCII escapes. Returns 0; a git error yields "(none)".
qs_files_block() {
	local base="$1" rev="${2:-}" out
	if [ -n "$rev" ]; then
		out="$(git -c core.quotePath=true diff --name-status -M "$base" "$rev" 2>/dev/null || true)"
	else
		out="$(git -c core.quotePath=true diff --cached --name-status -M "$base" 2>/dev/null || true)"
	fi
	echo "Files:"
	if [ -z "$out" ]; then
		echo "(none)"
		return 0
	fi
	printf '%s\n' "$out" | awk -F '\t' '{
		s = substr($1, 1, 1)
		if ((s == "R" || s == "C") && NF >= 3) print s " " $2 " -> " $3
		else print s " " $2
	}'
}

# qs_commit_is_amend SOURCE ARG3: succeed when the commit being prepared is an amend. SOURCE and
# ARG3 are the 2nd and 3rd arguments of prepare-commit-msg (empty in commit-msg). git passes
# "commit HEAD" for --amend, but only "message" for `--amend -m`, so the parent process command
# line (/proc, best effort) is also checked.
qs_commit_is_amend() {
	local source="${1:-}" arg3="${2:-}" cmd
	{ [ "$source" = commit ] && [ "$arg3" = HEAD ]; } && return 0
	if [ -r "/proc/$PPID/cmdline" ]; then
		cmd="$(tr '\0' ' ' <"/proc/$PPID/cmdline" 2>/dev/null || true)"
		case " $cmd" in *" commit "*" --amend "* | *" commit --amend "*) return 0 ;; esac
	fi
	return 1
}

# qs_commit_files_block SOURCE ARG3: print the Files block of the commit being made: index vs
# HEAD (merge: first parent, which is HEAD; amend: HEAD^; root commit: the empty tree).
qs_commit_files_block() {
	local base
	if qs_commit_is_amend "${1:-}" "${2:-}"; then
		base="$(git rev-parse -q --verify HEAD^ 2>/dev/null || qs_empty_tree)"
	else
		base="$(git rev-parse -q --verify HEAD 2>/dev/null || qs_empty_tree)"
	fi
	qs_files_block "$base"
}

# qs_files_store BLOCK: remember BLOCK in .git/quality-suite/FILES_BLOCK, tagged with the index
# tree it was computed for, so commit-msg can restore it. Returns 0.
qs_files_store() {
	local dir tree
	dir="$(git rev-parse --git-path quality-suite)"
	mkdir -p "$dir" 2>/dev/null || return 0
	tree="$(git write-tree 2>/dev/null || echo none)"
	{
		echo "$tree"
		printf '%s\n' "$1"
	} >"$dir/FILES_BLOCK"
}

# qs_files_stored: print the stored block when it was computed for the current index tree;
# always removes the stored file. Returns 1 when there is no usable block.
qs_files_stored() {
	local dir f tree
	dir="$(git rev-parse --git-path quality-suite)"
	f="$dir/FILES_BLOCK"
	[ -f "$f" ] || return 1
	tree="$(git write-tree 2>/dev/null || echo none)"
	if [ "$(head -n1 "$f")" = "$tree" ]; then
		tail -n +2 "$f"
		rm -f "$f"
		return 0
	fi
	rm -f "$f"
	return 1
}

# qs_message_get_files MSGFILE: print the existing Files block of the message (the "Files:" line
# and the lines up to the next blank or comment line); prints nothing when there is none.
qs_message_get_files() {
	local cc
	cc="$(qs_comment_char)"
	awk -v cc="$cc" '
		infiles && ($0 == "" || index($0, cc) == 1) { exit }
		infiles { print; next }
		$0 == "Files:" { infiles = 1; print }
	' "$1"
}

# qs_is_skippable LINE CC: succeed when LINE is blank or a comment line (starts with CC).
qs_is_skippable() {
	[ -z "$1" ] || [ "${1:0:${#2}}" = "$2" ]
}

# qs_message_set_files MSGFILE BLOCK: rewrite MSGFILE so it has exactly one Files block, BLOCK.
# An existing block is replaced; otherwise it goes before the trailer paragraph (the last
# paragraph, when it is not the subject and is all "Key: value" lines) or after the last
# message line. Comment lines (core.commentChar) are never touched. Returns 0.
qs_message_set_files() {
	local file="$1" block="$2" cc line skipping=0 i n last=-1 p first=-1 trailer=1 out
	local -a src=() body=()
	cc="$(qs_comment_char)"
	while IFS= read -r line || [ -n "$line" ]; do src+=("$line"); done <"$file"
	# 1. drop the existing block (and one of the blank lines around it)
	for line in "${src[@]+"${src[@]}"}"; do
		if [ "$skipping" = 1 ]; then
			if qs_is_skippable "$line" "$cc"; then
				skipping=0
				# why: avoid two blank lines where the block was
				if [ -z "$line" ] && [ "${#body[@]}" -gt 0 ] && [ -z "${body[${#body[@]} - 1]}" ]; then continue; fi
			else
				continue
			fi
		elif [ "$line" = "Files:" ]; then
			skipping=1
			continue
		fi
		body+=("$line")
	done
	n=${#body[@]}
	# 2. first and last message line (comments and blanks do not count)
	for ((i = 0; i < n; i++)); do
		qs_is_skippable "${body[$i]}" "$cc" && continue
		[ "$first" -lt 0 ] && first=$i
		last=$i
	done
	if [ "$last" -lt 0 ]; then
		printf '%s\n' "$block" >"$file"
		return 0
	fi
	# 3. start of the last paragraph and whether it is a trailer paragraph
	p=$last
	while [ "$p" -gt 0 ]; do
		qs_is_skippable "${body[$((p - 1))]}" "$cc" && break
		p=$((p - 1))
	done
	if [ "$p" -le "$first" ]; then
		trailer=0
	else
		for ((i = p; i <= last; i++)); do
			printf '%s\n' "${body[$i]}" | grep -qE '^([A-Za-z][A-Za-z0-9-]*: |[[:space:]])' || trailer=0
		done
	fi
	out="$(mktemp)"
	{
		if [ "$trailer" = 1 ]; then
			for ((i = 0; i < p; i++)); do printf '%s\n' "${body[$i]}"; done
			printf '%s\n\n' "$block"
			for ((i = p; i < n; i++)); do printf '%s\n' "${body[$i]}"; done
		else
			for ((i = 0; i <= last; i++)); do printf '%s\n' "${body[$i]}"; done
			printf '\n%s\n' "$block"
			i=$((last + 1))
			while [ "$i" -lt "$n" ] && [ -z "${body[$i]}" ]; do i=$((i + 1)); done
			if [ "$i" -lt "$n" ]; then
				echo
				for (( ; i < n; i++)); do printf '%s\n' "${body[$i]}"; done
			fi
		fi
	} >"$out"
	cat "$out" >"$file"
	rm -f "$out"
}

# qs_commit_files_enforce MSGFILE: commit-msg step. Mode off: nothing. Otherwise the expected
# block is the one stored by prepare-commit-msg (or computed from the index when the hook did
# not run, e.g. some rebase steps). Mode block: insert a missing block or restore an edited one,
# saying so on stderr. Mode warn: only warn when the block is missing. Returns 0.
qs_commit_files_enforce() {
	local file="$1" mode="${QS_COMMIT_FILES:-block}" want have
	[ "$mode" = off ] && return 0
	have="$(qs_message_get_files "$file")"
	if [ "$mode" = warn ]; then
		[ -n "$have" ] || echo "commit-msg: warning: the message has no Files: block (commit.files = warn)." >&2
		rm -f "$(git rev-parse --git-path quality-suite)/FILES_BLOCK"
		return 0
	fi
	want="$(qs_files_stored || qs_commit_files_block "" "")"
	[ "$have" = "$want" ] && return 0
	if [ -z "$have" ]; then
		echo "commit-msg: added the Files: block (commit.files = block)." >&2
	else
		echo "commit-msg: restored the Files: block computed from the staged files." >&2
	fi
	qs_message_set_files "$file" "$want"
}
