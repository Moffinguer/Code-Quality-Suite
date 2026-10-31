#!/usr/bin/env bash
# jsp.sh - JSP. Honest note: JSP (HTML + <% %> scriptlets, tags and ${} EL) has no
# reliable standard formatter/linter; HTML parsers break on scriptlets. So this does
# NOT format; it only checks delimiter balance, which catches the most common error.
set -euo pipefail
files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0
echo "  -> [jsp] basic check (JSP has no standard linter)"
rc=0
for f in "${files[@]}"; do
  open=$(grep -o '<%' "$f" | wc -l | tr -d ' ')
  close=$(grep -o '%>' "$f" | wc -l | tr -d ' ')
  if [ "$open" -ne "$close" ]; then
    echo "     $f: unbalanced <% %> delimiters ($open open, $close close)"
    rc=1
  fi
done
exit "$rc"
