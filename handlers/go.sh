#!/usr/bin/env bash
# go.sh - gofmt (format/check, per file) + go vet / staticcheck (package-level,
# only when a go.mod module is found; Go's static tools are package-oriented).
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
has_mod() { local d; d="$(cd "$(dirname "$1")" && pwd)"; while [ "$d" != "/" ]; do [ -f "$d/go.mod" ] && return 0; d="$(dirname "$d")"; done; return 1; }
dirs=""
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v gofmt &>/dev/null; then
    if [ "$MODE" = "fix" ]; then gofmt -w "$f" || true
    elif [ -n "$(gofmt -l "$f" 2>/dev/null)" ]; then echo "[quality-suite:go] not gofmt-formatted: $f"; rc=1; fi
  fi
  if has_mod "$f"; then d="$(dirname "$f")"; case " $dirs " in *" $d "*) ;; *) dirs="$dirs $d";; esac; fi
done
for d in $dirs; do
  if command -v staticcheck &>/dev/null; then
    ( cd "$d" && staticcheck ./... ) || { echo "[quality-suite:go] staticcheck issues in: $d"; rc=1; }
  elif command -v go &>/dev/null; then
    ( cd "$d" && go vet ./... ) || { echo "[quality-suite:go] go vet issues in: $d"; rc=1; }
  fi
done
exit "$rc"
