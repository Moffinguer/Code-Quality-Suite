#!/usr/bin/env bash
# =============================================================================
# handlers/sql.sh — Handler para archivos SQL (Oracle)
# =============================================================================
set -euo pipefail

SUITE_DIR="/opt/quality-suite"
CONFIG_FILE="${SUITE_DIR}/config/.sqlfluff"
MODE="${QUALITY_MODE:-fix}"

if [[ "$#" -eq 0 ]]; then
  exit 0
fi

rc=0

for f in "$@"; do
  [[ -f "$f" ]] || continue

  if [[ "$MODE" == "fix" ]]; then
    echo "[quality-suite:sql] Formateando $f con sqlfluff (dialecto Oracle)..."
    sqlfluff format --config "$CONFIG_FILE" "$f" || true
  fi

  echo "[quality-suite:sql] Analizando $f con sqlfluff..."
  if ! sqlfluff lint --config "$CONFIG_FILE" "$f"; then
    echo "[quality-suite:sql] Violaciones de estilo/linting SQL en: $f"
    rc=1
  fi
done

exit "$rc"
