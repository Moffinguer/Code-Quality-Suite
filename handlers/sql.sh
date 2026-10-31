#!/usr/bin/env bash
# sql.sh - sqlfluff: format on fix, then lint. Dialect from SQL_DIALECT (default oracle).
set -euo pipefail
CONFIG_FILE="/opt/quality-suite/config/.sqlfluff"
MODE="${QUALITY_MODE:-fix}"
DIALECT="${SQL_DIALECT:-oracle}"
[ "$#" -eq 0 ] && exit 0
rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "fix" ]; then
    echo "[quality-suite:sql] Formatting $f (dialect $DIALECT)..."
    sqlfluff format --config "$CONFIG_FILE" --dialect "$DIALECT" "$f" || true
  fi
  echo "[quality-suite:sql] Linting $f (dialect $DIALECT)..."
  if ! sqlfluff lint --config "$CONFIG_FILE" --dialect "$DIALECT" "$f"; then echo "[quality-suite:sql] SQL lint violations in: $f"; rc=1; fi
done
exit "$rc"
