#!/usr/bin/env bash
# =============================================================================
# handlers/shell.sh — Handler para scripts Shell (shfmt, shellcheck)
# =============================================================================
set -euo pipefail

MODE="${QUALITY_MODE:-fix}"

if [[ "$#" -eq 0 ]]; then
  exit 0
fi

rc=0

for f in "$@"; do
  [[ -f "$f" ]] || continue

  if [[ "$MODE" == "fix" ]]; then
    if command -v shfmt &>/dev/null; then
      shfmt -w -s "$f" || true
    fi
  else
    if command -v shfmt &>/dev/null; then
      if ! shfmt -d -s "$f"; then
        echo "[quality-suite:shell] Error de formato shfmt en: $f"
        rc=1
      fi
    fi
  fi

  if command -v shellcheck &>/dev/null; then
    if ! shellcheck -x "$f"; then
      echo "[quality-suite:shell] Violaciones de ShellCheck en: $f"
      rc=1
    fi
  fi
done

exit "$rc"
