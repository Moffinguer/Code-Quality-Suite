#!/usr/bin/env bash
# vim.sh - Vimscript: a basic, safe formatter (trailing whitespace + final newline)
# plus vint (lint). why: shfmt is shell-only and would corrupt Vimscript, and
# Vimscript has no standard reindenter, so the format pass is a safe minimal cleanup.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "fix" ]; then
    sed -i 's/[[:space:]]*$//' "$f"                       # strip trailing whitespace
    [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ] && printf '\n' >> "$f"  # ensure final newline
  else
    if grep -nE '[[:space:]]+$' "$f" >/dev/null; then echo "[quality-suite:vim] trailing whitespace in: $f"; rc=1; fi
    if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then echo "[quality-suite:vim] missing final newline in: $f"; rc=1; fi
  fi
  if command -v vint &>/dev/null; then
    vint "$f" || { echo "[quality-suite:vim] vint issues in: $f"; rc=1; }
  fi
done
exit "$rc"
