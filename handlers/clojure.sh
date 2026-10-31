#!/usr/bin/env bash
# clojure.sh - cljfmt (format/check) + clj-kondo (lint).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v cljfmt &>/dev/null; then
    if [ "$MODE" = "fix" ]; then cljfmt fix "$f" || true
    else cljfmt check "$f" || { echo "[quality-suite:clojure] not formatted: $f"; rc=1; }; fi
  fi
  if command -v clj-kondo &>/dev/null; then
    clj-kondo --lint "$f" || { echo "[quality-suite:clojure] clj-kondo issues in: $f"; rc=1; }
  fi
done
exit "$rc"
