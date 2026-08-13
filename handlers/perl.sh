#!/usr/bin/env bash
# =============================================================================
# handlers/perl.sh — Handler para archivos Perl (.pl, .pm, .t)
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

  # 1. Validación sintáctica
  if ! perl -cw "$f" 2>&1; then
    echo "[quality-suite:perl] Error de sintaxis en: $f"
    rc=1
    continue
  fi

  if [[ "$MODE" == "fix" ]]; then
    # 2. Formateo de imports
    if command -v perlimports &>/dev/null; then
      perlimports --configFile "${CONFIG_DIR}/perlimports.toml" --filename "$f" --inplace 2>/dev/null || true
    fi

    # 3. Formateo de código con perltidy
    if command -v perltidy &>/dev/null; then
      perltidy -pro="${CONFIG_DIR}/.perltidyrc" -b -bext=/ "$f" 2>/dev/null || true
    fi
  fi

  # 4. Análisis estático con perlcritic
  if command -v perlcritic &>/dev/null; then
    if ! perlcritic --profile "${CONFIG_DIR}/.perlcriticrc" "$f"; then
      echo "[quality-suite:perl] Violaciones de Perl::Critic en: $f"
      rc=1
    fi
  fi
done

exit "$rc"
