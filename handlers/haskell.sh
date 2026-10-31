#!/usr/bin/env bash
# haskell.sh - fourmolu (format/check) + hlint (lint). Both standalone binaries.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v fourmolu &>/dev/null; then
    if [ "$MODE" = "fix" ]; then fourmolu -i "$f" || true
    else fourmolu --mode check "$f" || { echo "[quality-suite:haskell] not formatted: $f"; rc=1; }; fi
  fi
  if command -v hlint &>/dev/null; then
    hlint "$f" || { echo "[quality-suite:haskell] hlint issues in: $f"; rc=1; }
  fi
done
exit "$rc"
