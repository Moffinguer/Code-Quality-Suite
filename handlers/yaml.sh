#!/usr/bin/env bash
# yaml.sh - yamlfmt (format/check) + yamllint (lint).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v yamlfmt &>/dev/null; then
    if [ "$MODE" = "fix" ]; then yamlfmt "$f" || true
    else yamlfmt -lint "$f" || { echo "[quality-suite:yaml] not formatted: $f"; rc=1; }; fi
  fi
  if command -v yamllint &>/dev/null; then
    yamllint -s "$f" || { echo "[quality-suite:yaml] yamllint issues in: $f"; rc=1; }
  fi
done
exit "$rc"
