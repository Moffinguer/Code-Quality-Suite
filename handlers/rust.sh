#!/usr/bin/env bash
# rust.sh - rustfmt (format/check, per file) + clippy (crate-level, best-effort).
# RUST_EDITION sets the edition rustfmt/clippy assume.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
RUST_EDITION="${RUST_EDITION:-2021}"
crates=""
find_crate() { local d; d="$(dirname "$1")"; while [ "$d" != "/" ] && [ "$d" != "." ]; do [ -f "$d/Cargo.toml" ] && { echo "$d"; return; }; d="$(dirname "$d")"; done; }
for f in "$@"; do
  [ -f "$f" ] || continue
  if command -v rustfmt &>/dev/null; then
    if [ "$MODE" = "fix" ]; then rustfmt --edition "$RUST_EDITION" "$f" || true
    else rustfmt --edition "$RUST_EDITION" --check "$f" || { echo "[quality-suite:rust] not rustfmt-formatted: $f"; rc=1; }; fi
  fi
  c="$(find_crate "$f" || true)"; [ -n "$c" ] && case " $crates " in *" $c "*) ;; *) crates="$crates $c";; esac
done
if command -v cargo &>/dev/null; then
  for c in $crates; do ( cd "$c" && cargo clippy --quiet -- -D warnings ) || { echo "[quality-suite:rust] clippy issues in: $c"; rc=1; }; done
fi
exit "$rc"
