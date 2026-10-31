#!/usr/bin/env bash
# shell.sh - native syntax analysis (bash -n) + shfmt (format/check) + shellcheck.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"
[ "$#" -eq 0 ] && exit 0
rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  # native: bash's own parser (no execution, writes nothing)
  bash -n "$f" 2>/tmp/shnat || { echo "[quality-suite:shell] native syntax error in: $f"; sed 's/^/    /' /tmp/shnat; rc=1; continue; }
  if [ "$MODE" = "fix" ]; then
    command -v shfmt &>/dev/null && shfmt -w -s "$f" || true
  else
    command -v shfmt &>/dev/null && { shfmt -d -s "$f" || { echo "[quality-suite:shell] shfmt format error in: $f"; rc=1; }; }
  fi
  command -v shellcheck &>/dev/null && { shellcheck -x "$f" || { echo "[quality-suite:shell] ShellCheck violations in: $f"; rc=1; }; }
done
exit "$rc"
