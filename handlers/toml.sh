#!/usr/bin/env bash
# toml.sh - taplo: format (fix) or check, then lint.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
command -v taplo &>/dev/null || { echo "[toml] taplo not installed"; exit 0; }
for f in "$@"; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "fix" ]; then taplo fmt "$f" || true
  else taplo fmt --check "$f" || { echo "[quality-suite:toml] not formatted: $f"; rc=1; }; fi
  taplo lint "$f" || { echo "[quality-suite:toml] lint issues in: $f"; rc=1; }
done
exit "$rc"
