#!/usr/bin/env bash
# rst.sh - reStructuredText: rstfmt (format on fix) + rstcheck (lint).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "fix" ] && command -v rstfmt &>/dev/null; then rstfmt "$f" || true; fi
  if command -v rstcheck &>/dev/null; then
    rstcheck "$f" || { echo "[quality-suite:rst] issues in: $f"; rc=1; }
  fi
done
exit "$rc"
