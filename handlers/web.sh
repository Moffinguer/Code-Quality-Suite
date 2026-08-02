#!/usr/bin/env bash
# =============================================================================
# handlers/web.sh — HTML, XHTML, JS, JSX, TS, TSX, CSS, SCSS (y JS/TS/CSS
# embebidos dentro de HTML).
#   Formatea con Prettier (maneja el codigo embebido en HTML automaticamente).
#   Lintea: ESLint (JS/TS/HTML), Stylelint (CSS/SCSS/HTML), html-validate (HTML).
#   QUALITY_MODE=fix formatea in-place; =check verifica sin tocar.
# =============================================================================
set -euo pipefail

WT="${WEBTOOLS_DIR:-/opt/webtools}"
BIN="$WT/node_modules/.bin"
MODE="${QUALITY_MODE:-fix}"

files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0
rc=0

# Sub-buckets por tipo de lint (Prettier va sobre todos).
esl=(); sty=(); htmlv=()
for f in "${files[@]}"; do
  case "$f" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.html|*.htm|*.xhtml) esl+=("$f") ;;
  esac
  case "$f" in
    *.css|*.scss|*.html|*.htm|*.xhtml) sty+=("$f") ;;
  esac
  case "$f" in
    *.html|*.htm|*.xhtml) htmlv+=("$f") ;;
  esac
done

# 1) Prettier (formato; incluye JS/TS/CSS embebidos en HTML)
if [ "$MODE" = "check" ]; then
  echo "  -> [web] prettier --check"
  "$BIN/prettier" --config "$WT/.prettierrc.json" --check "${files[@]}" || rc=1
else
  echo "  -> [web] prettier --write"
  "$BIN/prettier" --config "$WT/.prettierrc.json" --write "${files[@]}"
fi

# 2) ESLint (JS/TS + JS embebido en HTML)
if [ "${#esl[@]}" -gt 0 ]; then
  echo "  -> [web] eslint"
  "$BIN/eslint" --config "$WT/eslint.config.mjs" "${esl[@]}" || rc=1
fi

# 3) Stylelint (CSS/SCSS + CSS embebido en HTML)
if [ "${#sty[@]}" -gt 0 ]; then
  echo "  -> [web] stylelint"
  "$BIN/stylelint" --config "$WT/.stylelintrc.json" "${sty[@]}" || rc=1
fi

# 4) html-validate (estructura HTML/XHTML)
if [ "${#htmlv[@]}" -gt 0 ]; then
  echo "  -> [web] html-validate"
  "$BIN/html-validate" --config "$WT/.htmlvalidate.json" "${htmlv[@]}" || rc=1
fi

exit "$rc"
