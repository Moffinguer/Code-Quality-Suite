#!/usr/bin/env bash
# env.sh - .env files: dotenv-linter (lint; --fix on fix mode).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
command -v dotenv-linter &>/dev/null || { echo "[env] dotenv-linter not installed"; exit 0; }
for f in "$@"; do
  [ -f "$f" ] || continue
  [ "$MODE" = "fix" ] && dotenv-linter fix "$f" >/dev/null 2>&1 || true
  dotenv-linter "$f" || { echo "[quality-suite:env] issues in: $f"; rc=1; }
done
exit "$rc"
