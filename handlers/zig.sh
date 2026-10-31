#!/usr/bin/env bash
# zig.sh - zig fmt (format/check) + zig ast-check (parse/analyze).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
command -v zig &>/dev/null || { echo "[zig] zig not installed"; exit 0; }
for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in *.zon) [ "$MODE" = fix ] && zig fmt "$f" || zig fmt --check "$f" || { echo "[quality-suite:zig] not formatted: $f"; rc=1; }; continue;; esac
  if [ "$MODE" = "fix" ]; then zig fmt "$f" || true
  else zig fmt --check "$f" || { echo "[quality-suite:zig] not formatted: $f"; rc=1; }; fi
  zig ast-check "$f" || { echo "[quality-suite:zig] ast-check issues in: $f"; rc=1; }
done
exit "$rc"
