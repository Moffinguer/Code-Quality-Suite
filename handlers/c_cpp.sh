#!/usr/bin/env bash
# =============================================================================
# handlers/c_cpp.sh — Handler para C/C++ (clang-format, cppcheck, clang-tidy)
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
    if command -v clang-format &>/dev/null; then
      clang-format --style=file:"${CONFIG_DIR}/.clang-format" -i "$f"
    fi
  else
    if command -v clang-format &>/dev/null; then
      if ! clang-format --style=file:"${CONFIG_DIR}/.clang-format" --dry-run --Werror "$f"; then
        echo "[quality-suite:c_cpp] Formato incorrecto en: $f"
        rc=1
      fi
    fi
  fi

  if command -v cppcheck &>/dev/null; then
    if ! cppcheck --enable=all --suppress=missingIncludeSystem --quiet --error-exitcode=1 "$f"; then
      echo "[quality-suite:c_cpp] Violaciones de Cppcheck en: $f"
      rc=1
    fi
  fi

  if command -v clang-tidy &>/dev/null; then
    if ! clang-tidy --config-file="${CONFIG_DIR}/.clang-tidy" "$f" -- 2>/dev/null; then
      echo "[quality-suite:c_cpp] Violaciones de Clang-Tidy en: $f"
      rc=1
    fi
  fi
done

exit "$rc"
