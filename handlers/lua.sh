#!/usr/bin/env bash
# lua.sh - native syntax analysis (luac -p) + StyLua (format/check) + luacheck.
# LUA_VERSION sets luacheck --std.
set -euo pipefail
MODE="${QUALITY_MODE:-fix}"; [ "$#" -eq 0 ] && exit 0; rc=0
LUA_VERSION="${LUA_VERSION:-}"
std=(); case "$LUA_VERSION" in 5.1) std=(--std lua51);; 5.2) std=(--std lua52);; 5.3) std=(--std lua53);; 5.4) std=(--std lua54);; luau|Luau) std=(--std luau);; esac
LUAC="$(command -v luac5.4 || command -v luac || true)"
for f in "$@"; do
  [ -f "$f" ] || continue
  # native: the Lua compiler's parse-only mode (writes nothing)
  if [ -n "$LUAC" ]; then "$LUAC" -p "$f" 2>/tmp/luanat || { echo "[quality-suite:lua] native syntax error in: $f"; sed 's/^/    /' /tmp/luanat; rc=1; continue; }; fi
  if command -v stylua &>/dev/null; then
    if [ "$MODE" = "fix" ]; then stylua "$f" || true
    else stylua --check "$f" || { echo "[quality-suite:lua] not formatted: $f"; rc=1; }; fi
  fi
  command -v luacheck &>/dev/null && { luacheck "${std[@]}" "$f" || { echo "[quality-suite:lua] luacheck issues in: $f"; rc=1; }; }
done
exit "$rc"
