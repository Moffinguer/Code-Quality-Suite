#!/usr/bin/env bash
# dockerfile.sh - hadolint (no formatting; same in fix and check).
set -euo pipefail
CONFIG="/opt/quality-suite/config/.hadolint.yaml"
files=("$@"); [ "${#files[@]}" -eq 0 ] && exit 0
echo "  -> [docker] hadolint"; rc=0
for f in "${files[@]}"; do hadolint --config "${CONFIG}" "$f" || rc=1; done
exit "${rc}"
