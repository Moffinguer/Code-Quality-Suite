#!/usr/bin/env bash
# c_cpp.sh - clang-format (verify in check), cppcheck, clang-tidy.
set -euo pipefail
CONFIG_DIR="/opt/quality-suite/config"
MODE="${QUALITY_MODE:-fix}"
[ "$#" -eq 0 ] && exit 0
rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "fix" ]; then
    command -v clang-format &>/dev/null && clang-format --style=file:"${CONFIG_DIR}/.clang-format" -i "$f" || true
  else
    if command -v clang-format &>/dev/null && ! clang-format --style=file:"${CONFIG_DIR}/.clang-format" --dry-run --Werror "$f"; then
      echo "[quality-suite:c_cpp] Incorrect format in: $f"; rc=1; fi
  fi
  if command -v cppcheck &>/dev/null; then
    if ! cppcheck --enable=all --suppress=missingIncludeSystem --quiet --error-exitcode=1 "$f"; then
      echo "[quality-suite:c_cpp] Cppcheck violations in: $f"; rc=1; fi
  fi
  if command -v clang-tidy &>/dev/null; then
    if ! clang-tidy --config-file="${CONFIG_DIR}/.clang-tidy" "$f" -- 2>/dev/null; then
      echo "[quality-suite:c_cpp] Clang-Tidy violations in: $f"; rc=1; fi
  fi
done
exit "$rc"
