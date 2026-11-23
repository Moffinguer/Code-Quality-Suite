#!/usr/bin/env bash
# qs-common.sh - helpers shared by the suite scripts: tagged messages, ref checks, confirmation.
# Source it; it defines functions only and changes no shell option.
#   QS_TAG  prefix of the messages (set it before calling qs_die / qs_say); default "quality-suite"

# qs_die MESSAGE...: print "[<QS_TAG>] <message>" to stderr and exit 1.
# Arguments: the words of the message. Errors: always exits the shell with status 1.
qs_die() {
	echo "[${QS_TAG:-quality-suite}] $*" >&2
	exit 1
}

# qs_say MESSAGE...: print "[<QS_TAG>] <message>" to stdout.
# Arguments: the words of the message. Return value: 0.
qs_say() {
	echo "[${QS_TAG:-quality-suite}] $*"
}

# qs_python: print the name of the first of python3, python, py that runs AND is Python 3 (the
# Windows Store python3 stub exists on Git Bash but fails; Windows often has only `python`).
# Arguments: none. Return value: 0 and the command name on stdout, 1 (nothing printed) if none.
qs_python() {
	local py
	for py in python3 python py; do
		if command -v "$py" >/dev/null 2>&1 &&
			"$py" -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
			printf '%s' "$py"
			return 0
		fi
	done
	return 1
}

# qs_ref_exists REF: tell whether REF names an existing object in the current repository.
# Arguments: $1 a ref or revision (branch, tag, sha, refs/heads/x).
# Return value: 0 when it resolves, 1 otherwise. Never prints.
qs_ref_exists() {
	git rev-parse -q --verify "$1" >/dev/null 2>&1
}

# qs_confirm QUESTION: ask "<QUESTION> [y/N] " on the terminal.
# Arguments: $1 the question. Environment: YES=1 answers yes without asking.
# Return value: 0 for y, Y, s, S, yes or si; 1 for anything else (also when there is no tty).
qs_confirm() {
	[ "${YES:-0}" = 1 ] && return 0
	local r
	printf '%s [y/N] ' "$1" >/dev/tty
	read -r r </dev/tty || r=""
	case "$r" in y | Y | s | S | yes | si) return 0 ;; esac
	return 1
}
