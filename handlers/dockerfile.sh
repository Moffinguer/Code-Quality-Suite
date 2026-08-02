#!/usr/bin/env bash
# =============================================================================
# handlers/dockerfile.sh — hadolint (no formatea; igual en fix y check).
# =============================================================================
set -euo pipefail

CONFIG="/opt/quality-suite/config/.hadolint.yaml"
files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0

echo "  -> [docker] hadolint"
rc=0
for f in "${files[@]}"; do
  hadolint --config "${CONFIG}" "$f" || rc=1
done
exit "${rc}"
