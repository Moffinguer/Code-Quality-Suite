#!/usr/bin/env bash
# xml.sh - XML validation and formatting with xmllint (libxml2).
#   Always: well-formedness check.  Optional: schema validation if XML_SCHEMA
#   points to a local .xsd.  fix: reindents in place.  check: fails if not formatted.
# Env: XML_FORMAT=1|0  XML_INDENT=2  XML_SCHEMA=/path/schema.xsd
# why XML_FORMAT=0 exists: reformatting can alter significant whitespace in
# mixed-content XML (xml:space="preserve"); use 0 there (validate only).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"
XML_FORMAT="${XML_FORMAT:-1}"
XML_INDENT="${XML_INDENT:-2}"
XML_SCHEMA="${XML_SCHEMA:-}"
files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0
sp=""; i=0; while [ "$i" -lt "$XML_INDENT" ]; do sp="$sp "; i=$((i+1)); done
export XMLLINT_INDENT="$sp"
echo "  -> [xml] xmllint (${MODE})"
rc=0
for f in "${files[@]}"; do
  if ! xmllint --noout "$f" 2>/tmp/xmlerr; then
    echo "     $f: not well-formed"; sed 's/^/       /' /tmp/xmlerr; rc=1; continue
  fi
  if [ -n "$XML_SCHEMA" ] && [ -f "$XML_SCHEMA" ]; then
    xmllint --noout --schema "$XML_SCHEMA" "$f" 2>/tmp/xmlerr \
      || { echo "     $f: does not validate against $XML_SCHEMA"; sed 's/^/       /' /tmp/xmlerr; rc=1; }
  fi
  if [ "$XML_FORMAT" = "1" ]; then
    if [ "$MODE" = "check" ]; then
      xmllint --format "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 \
        || { echo "     $f: not formatted"; rc=1; }
    else
      tmp="$(mktemp)"
      if xmllint --format "$f" > "$tmp" 2>/dev/null; then mv "$tmp" "$f"; else rm -f "$tmp"; fi
    fi
  fi
done
exit "$rc"
