#!/usr/bin/env bash
# php.sh - php -l (syntax) + php-cs-fixer (format/check) + phpstan (static, best-effort).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v php &>/dev/null; then php -l "$f" >/dev/null || { echo "[quality-suite:php] syntax error in: $f"; rc=1; continue; }; fi
  if command -v php-cs-fixer &>/dev/null; then
    if [ "$MODE" = "fix" ]; then php-cs-fixer fix "$f" >/dev/null 2>&1 || true
    else php-cs-fixer fix --dry-run --diff "$f" >/dev/null 2>&1 || { echo "[quality-suite:php] not formatted: $f"; rc=1; }; fi
  fi
  if command -v phpstan &>/dev/null; then
    phpstan analyse --no-progress --no-ansi "$f" >/dev/null 2>&1 || { echo "[quality-suite:php] phpstan issues in: $f"; rc=1; }
  fi
done
exit "$rc"
