#!/usr/bin/env bash
# properties.sh - .properties: basic static check (no standard tool).
# Verifies each line is a comment (# or !), blank, or key=value / key:value, and
# reports duplicate keys.
set -euo pipefail
[ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  awk -v F="$f" '
    /^[[:space:]]*($|#|!)/ { next }
    { if ($0 !~ /[=:]/) { printf "[quality-suite:properties] %s:%d malformed (no key=value): %s\n", F, NR, $0; bad=1; next }
      key=$0; sub(/[=:].*/,"",key); gsub(/^[[:space:]]+|[[:space:]]+$/,"",key)
      if (key=="") { printf "[quality-suite:properties] %s:%d empty key\n", F, NR; bad=1; next }
      if (seen[key]++) { printf "[quality-suite:properties] %s:%d duplicate key: %s\n", F, NR, key; bad=1 } }
    END { exit bad?1:0 }' "$f" || rc=1
done
exit "$rc"
