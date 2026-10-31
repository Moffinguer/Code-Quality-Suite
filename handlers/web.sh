#!/usr/bin/env bash
# web.sh - native JS syntax analysis (node --check) + Prettier + ESLint/Stylelint/
# html-validate. fix writes; check verifies.
set -euo pipefail
WT="${WEBTOOLS_DIR:-/opt/webtools}"; BIN="$WT/node_modules/.bin"; MODE="${QUALITY_MODE:-fix}"
files=("$@"); [ "${#files[@]}" -eq 0 ] && exit 0
rc=0
esl=(); sty=(); htmlv=()
for f in "${files[@]}"; do
  # native: node's parser for plain JS (no execution; JSX/TS not supported here)
  case "$f" in
    *.js|*.mjs|*.cjs) command -v node &>/dev/null && { node --check "$f" 2>/tmp/jsnat || { echo "[quality-suite:web] native JS syntax error in: $f"; sed 's/^/    /' /tmp/jsnat; rc=1; }; } ;;
  esac
  case "$f" in *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.html|*.htm|*.xhtml) esl+=("$f") ;; esac
  case "$f" in *.css|*.scss|*.html|*.htm|*.xhtml) sty+=("$f") ;; esac
  case "$f" in *.html|*.htm|*.xhtml) htmlv+=("$f") ;; esac
done
if [ "$MODE" = "check" ]; then
  echo "  -> [web] prettier --check"; "$BIN/prettier" --config "$WT/.prettierrc.json" --check "${files[@]}" || rc=1
else
  echo "  -> [web] prettier --write"; "$BIN/prettier" --config "$WT/.prettierrc.json" --write "${files[@]}"
fi
[ "${#esl[@]}" -gt 0 ] && { echo "  -> [web] eslint"; "$BIN/eslint" --config "$WT/eslint.config.mjs" "${esl[@]}" || rc=1; }
[ "${#sty[@]}" -gt 0 ] && { echo "  -> [web] stylelint"; "$BIN/stylelint" --config "$WT/.stylelintrc.json" "${sty[@]}" || rc=1; }
[ "${#htmlv[@]}" -gt 0 ] && { echo "  -> [web] html-validate"; "$BIN/html-validate" --config "$WT/.htmlvalidate.json" "${htmlv[@]}" || rc=1; }
exit "$rc"
