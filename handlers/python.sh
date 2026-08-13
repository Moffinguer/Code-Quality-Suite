#!/usr/bin/env bash
# =============================================================================
# handlers/python.sh — Handler exhaustivo para archivos Python (.py)
# =============================================================================
set -euo pipefail

SUITE_DIR="/opt/quality-suite"
CONFIG_DIR="${SUITE_DIR}/config"
MODE="${QUALITY_MODE:-fix}"

if [[ "$#" -eq 0 ]]; then
  exit 0
fi

rc=0

for f in "$@"; do
  [[ -f "$f" ]] || continue

  if [[ "$MODE" == "fix" ]]; then
    command -v autopep8 &>/dev/null && autopep8 --in-place "$f" || true
    command -v unify &>/dev/null && unify --in-place "$f" || true
    command -v eradicate &>/dev/null && eradicate --in-place "$f" || true
    command -v isort &>/dev/null && isort "$f" || true
    command -v black &>/dev/null && black --quiet "$f" || true
  fi

  if command -v pylint &>/dev/null; then
    if ! pylint --rcfile="${CONFIG_DIR}/.pylintrc" "$f"; then
      echo "[quality-suite:python] Violaciones de Pylint en: $f"
      rc=1
    fi
  fi

  if command -v mypy &>/dev/null; then
    if ! mypy --ignore-missing-imports "$f"; then
      echo "[quality-suite:python] Errores de tipos de Mypy en: $f"
      rc=1
    fi
  fi
done

exit "$rc"
