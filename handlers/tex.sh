#!/usr/bin/env bash
# tex.sh - latexindent (format/check) + chktex (lint).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v latexindent &>/dev/null; then
    if [ "$MODE" = "fix" ]; then
      tmp="$(mktemp)"; latexindent -s "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    else
      latexindent -s "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 || { echo "[quality-suite:tex] not formatted: $f"; rc=1; }
    fi
  fi
  if command -v chktex &>/dev/null; then
    chktex -q -n1 "$f" 2>/dev/null | grep -q . && { echo "[quality-suite:tex] chktex warnings in: $f"; chktex -q "$f" 2>/dev/null; rc=1; } || true
  fi
done
exit "$rc"
