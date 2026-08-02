#!/usr/bin/env bash
# =============================================================================
# link-agent-files.sh — genera los ficheros por-herramienta desde un unico
# AGENTS.md, para no mantener 5 copias. Fuente de verdad: AGENTS.md.
#   Uso: ./link-agent-files.sh [ruta-al-repo]
# =============================================================================
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
[ -f AGENTS.md ] || { echo "No hay AGENTS.md en $ROOT" >&2; exit 1; }

# Claude Code: import (no duplica contenido).
if [ ! -e CLAUDE.md ]; then printf '@AGENTS.md\n' > CLAUDE.md; echo "  CLAUDE.md -> @AGENTS.md"; fi

# Gemini CLI: symlink en Linux/Mac, copia en Windows.
if [ ! -e GEMINI.md ]; then
  ln -s AGENTS.md GEMINI.md 2>/dev/null && echo "  GEMINI.md -> symlink" \
    || { cp AGENTS.md GEMINI.md; echo "  GEMINI.md -> copia"; }
fi

echo "Listo. Edita solo AGENTS.md; Cursor/Copilot/Codex/Cline ya lo leen nativo."
