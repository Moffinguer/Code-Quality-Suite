#!/usr/bin/env bash
# =============================================================================
# handlers/jsp.sh — JSP.
# Aviso honesto: JSP (HTML + scriptlets <% %>, tags y EL ${}) NO tiene un
# formateador/linter estandar fiable; los parsers de HTML se rompen con los
# scriptlets. Por eso aqui NO se formatea; solo se hace una comprobacion
# basica de balance de delimitadores, que atrapa el error mas comun.
# =============================================================================
set -euo pipefail
files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0

echo "  -> [jsp] comprobacion basica (JSP sin linter estandar)"
rc=0
for f in "${files[@]}"; do
  open=$(grep -o '<%' "$f" | wc -l | tr -d ' ')
  close=$(grep -o '%>' "$f" | wc -l | tr -d ' ')
  if [ "$open" -ne "$close" ]; then
    echo "     $f: delimitadores <% %> desbalanceados ($open abren, $close cierran)"
    rc=1
  fi
done
exit "$rc"
