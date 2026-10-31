#!/usr/bin/env bash
# python.sh - native syntax analysis (ast.parse) + fix (autopep8/isort/black) +
# check (black/isort verify) + pylint + mypy.
set -euo pipefail
CONFIG_DIR="/opt/quality-suite/config"
MODE="${QUALITY_MODE:-fix}"
[ "$#" -eq 0 ] && exit 0
rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  # native: the interpreter's own parser (read-only safe; writes nothing)
  if command -v python3 &>/dev/null; then
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/tmp/pynat \
      || { echo "[quality-suite:python] native syntax error in: $f"; sed 's/^/    /' /tmp/pynat; rc=1; continue; }
  fi
  if [ "$MODE" = "fix" ]; then
    command -v autopep8 &>/dev/null && autopep8 --in-place "$f" || true
    command -v isort &>/dev/null && isort "$f" || true
    command -v black &>/dev/null && black --quiet "$f" || true
  else
    if command -v black &>/dev/null && ! black --check --quiet "$f" 2>/dev/null; then echo "[quality-suite:python] Not black-formatted: $f"; rc=1; fi
    if command -v isort &>/dev/null && ! isort --check-only "$f" &>/dev/null; then echo "[quality-suite:python] Imports not sorted: $f"; rc=1; fi
  fi
  command -v pylint &>/dev/null && { pylint --rcfile="${CONFIG_DIR}/.pylintrc" "$f" || { echo "[quality-suite:python] Pylint violations in: $f"; rc=1; }; }
  command -v mypy &>/dev/null && { mypy --ignore-missing-imports "$f" || { echo "[quality-suite:python] Mypy type errors in: $f"; rc=1; }; }
done
exit "$rc"
