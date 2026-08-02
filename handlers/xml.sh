#!/usr/bin/env bash
# =============================================================================
# handlers/xml.sh — validacion y formateo de XML con xmllint (libxml2).
#   Siempre: comprobacion de buena formacion (well-formed).
#   Opcional: validacion contra esquema si XML_SCHEMA apunta a un .xsd local.
#   fix:   reindenta in-place.   check: falla si no esta ya formateado.
# Variables: XML_FORMAT=1|0  XML_INDENT=2  XML_SCHEMA=/ruta/esquema.xsd
#
# NOTA: el reformateo puede alterar espacios significativos en XML de contenido
# mixto (xml:space="preserve"). Para esos casos usa XML_FORMAT=0 (solo valida).
# =============================================================================
set -euo pipefail

MODE="${QUALITY_MODE:-fix}"
XML_FORMAT="${XML_FORMAT:-1}"
XML_INDENT="${XML_INDENT:-2}"
XML_SCHEMA="${XML_SCHEMA:-}"

files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0

# XMLLINT_INDENT controla la indentacion de --format.
sp=""; i=0; while [ "$i" -lt "$XML_INDENT" ]; do sp="$sp "; i=$((i+1)); done
export XMLLINT_INDENT="$sp"

echo "  -> [xml] xmllint (${MODE})"
rc=0
for f in "${files[@]}"; do
  # 1) Buena formacion (siempre bloquea)
  if ! xmllint --noout "$f" 2>/tmp/xmlerr; then
    echo "     $f: NO bien formado"; sed 's/^/       /' /tmp/xmlerr; rc=1; continue
  fi
  # 2) Validacion opcional contra esquema
  if [ -n "$XML_SCHEMA" ] && [ -f "$XML_SCHEMA" ]; then
    xmllint --noout --schema "$XML_SCHEMA" "$f" 2>/tmp/xmlerr \
      || { echo "     $f: no valida contra $XML_SCHEMA"; sed 's/^/       /' /tmp/xmlerr; rc=1; }
  fi
  # 3) Formateo
  if [ "$XML_FORMAT" = "1" ]; then
    if [ "$MODE" = "check" ]; then
      xmllint --format "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 \
        || { echo "     $f: no esta formateado"; rc=1; }
    else
      tmp="$(mktemp)"
      if xmllint --format "$f" > "$tmp" 2>/dev/null; then mv "$tmp" "$f"; else rm -f "$tmp"; fi
    fi
  fi
done
exit "$rc"
