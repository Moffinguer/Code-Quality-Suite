#!/usr/bin/env bash
# perl.sh - perl -cw, perlimports + perltidy on fix, Perl::Critic.
set -euo pipefail
CONFIG_DIR="/opt/quality-suite/config"
MODE="${QUALITY_MODE:-fix}"
[ "$#" -eq 0 ] && exit 0
rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if ! perl -cw "$f" 2>&1; then echo "[quality-suite:perl] Syntax error in: $f"; rc=1; continue; fi
  if [ "$MODE" = "fix" ]; then
    command -v perlimports &>/dev/null && perlimports --configFile "${CONFIG_DIR}/perlimports.toml" --filename "$f" --inplace 2>/dev/null || true
    command -v perltidy &>/dev/null && perltidy -pro="${CONFIG_DIR}/.perltidyrc" -b -bext=/ "$f" 2>/dev/null || true
  fi
  if command -v perlcritic &>/dev/null; then
    if ! perlcritic --profile "${CONFIG_DIR}/.perlcriticrc" "$f"; then echo "[quality-suite:perl] Perl::Critic violations in: $f"; rc=1; fi
  fi
done
exit "$rc"
