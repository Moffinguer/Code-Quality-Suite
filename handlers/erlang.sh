#!/usr/bin/env bash
# erlang.sh - erlfmt (format/check) + erlc syntax check.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v erlfmt &>/dev/null; then
    if [ "$MODE" = "fix" ]; then erlfmt -w "$f" || true
    else erlfmt -c "$f" || { echo "[quality-suite:erlang] not formatted: $f"; rc=1; }; fi
  fi
  if command -v erlc &>/dev/null; then
    out="$(mktemp -d)"; erlc -Wall -o "$out" "$f" 2>/tmp/erlcerr || { echo "[quality-suite:erlang] erlc issues in: $f"; sed 's/^/    /' /tmp/erlcerr; rc=1; }; rm -rf "$out"
  fi
done
exit "$rc"
