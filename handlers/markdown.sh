#!/usr/bin/env bash
# markdown.sh - markdownlint-cli2. fix (default) auto-fixes; check only verifies.
set -euo pipefail
CONFIG="/opt/quality-suite/config/.markdownlint.jsonc"
MODE="${QUALITY_MODE:-fix}"
files=("$@"); [ "${#files[@]}" -eq 0 ] && exit 0
rc=0
if [ "$MODE" = "check" ]; then
  echo "  -> [md] markdownlint-cli2 (check)"; markdownlint-cli2 --config "${CONFIG}" "${files[@]}" || rc=$?
else
  echo "  -> [md] markdownlint-cli2 --fix"; markdownlint-cli2 --config "${CONFIG}" --fix "${files[@]}" || rc=$?
fi
[ "${rc}" -eq 0 ] && exit 0 || exit 1
