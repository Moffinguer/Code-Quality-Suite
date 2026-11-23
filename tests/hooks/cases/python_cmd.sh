#!/usr/bin/env bash
# Case: qs_python finds `python` when python3 is missing, fails when none exists, and ai-init
# warns (instead of failing silently) when settings.json cannot be merged.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
# shellcheck source=scripts/qs-common.sh
. "$SUITE/scripts/qs-common.sh"

# why: a PATH holding every tool except Python, so only the shims below can answer
nopy="$T/nopy"
mkdir -p "$nopy"
IFS=: read -r -a dirs <<<"$PATH"
for d in "${dirs[@]}"; do
	[ -d "$d" ] || continue
	for f in "$d"/*; do
		b="${f##*/}"
		case "$b" in python* | py | py.exe | py3*) continue ;; esac
		[ -x "$f" ] && [ -f "$f" ] && [ ! -e "$nopy/$b" ] && ln -s "$f" "$nopy/$b" || true
	done
done
real="$(command -v python3 || command -v python)"
shim="$T/shim"
mkdir -p "$shim"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" >"$shim/python"
chmod +x "$shim/python"

out="$(PATH="$shim:$nopy" qs_python)" && [ "$out" = python ] &&
	ok "qs_python: finds python without python3" || fail "qs_python: got '$out'"
rc=0
out="$(PATH="$nopy" qs_python)" || rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && ok "qs_python: returns 1 with no Python" || fail "qs_python: rc=$rc out='$out'"

repo="$(mktemp -d "$T/pyrepo-XXXX")"
git init -q -b develop "$repo"
err="$(PATH="$nopy" bash "$SUITE/scripts/ai-init.sh" "$repo" 2>&1 >/dev/null)" || true
printf '%s' "$err" | grep -q 'WARN: no Python 3' &&
	ok "ai-init: warns when settings.json cannot be merged" || fail "ai-init: no WARN: $err"
