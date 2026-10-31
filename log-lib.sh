#!/usr/bin/env bash
# log-lib.sh - structured logging for the git hooks (host side). Same format as the
# engine's qslog.py, written to the same file.
# Greppable, normalized lines so every tool/hook message can be detected later.
#
# Env:
#   QUALITY_LOG_LEVEL   DEBUG|INFO|WARN|ERROR (default INFO)  what the log file records
#   QUALITY_LOG_CONSOLE DEBUG|INFO|WARN|ERROR (default WARN)  what is echoed on the terminal
#   QUALITY_LOG_FORMAT  text|json             (default text)
#   QUALITY_LOG_FILE    optional path; lines are appended there too
#
# Text line:  <ts> <LEVEL> comp=<c> [file=<f>] [action=<a>] [status=<s>] msg="..."
# JSON line:  {"ts":"..","level":"..","comp":"..","file":"..","action":"..","status":"..","msg":".."}
# Grep examples:  grep 'comp=python'   grep 'status=ERROR'   grep 'action=check'

_qs_lvlnum(){ case "${1:-INFO}" in DEBUG)echo 10;; INFO)echo 20;; WARN)echo 30;; ERROR)echo 40;; *)echo 20;; esac; }
_qs_now(){ date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "-"; }
_qs_jesc(){ printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r\n'; }

# qs_log <LEVEL> <comp> <msg> [file] [action] [status]
qs_log(){
  local level="$1" comp="$2" msg="${3:-}" file="${4:-}" action="${5:-}" status="${6:-}"
  local thr; thr="$(_qs_lvlnum "${QUALITY_LOG_LEVEL:-INFO}")"
  [ "$(_qs_lvlnum "$level")" -lt "$thr" ] && return 0
  local line
  if [ "${QUALITY_LOG_FORMAT:-text}" = "json" ]; then
    line="{\"ts\":\"$(_qs_now)\",\"level\":\"$level\",\"comp\":\"$(_qs_jesc "$comp")\""
    [ -n "$file" ]   && line="$line,\"file\":\"$(_qs_jesc "$file")\""
    [ -n "$action" ] && line="$line,\"action\":\"$(_qs_jesc "$action")\""
    [ -n "$status" ] && line="$line,\"status\":\"$(_qs_jesc "$status")\""
    line="$line,\"msg\":\"$(_qs_jesc "$msg")\"}"
  else
    line="$(_qs_now) $level comp=$comp"
    [ -n "$file" ]   && line="$line file=$file"
    [ -n "$action" ] && line="$line action=$action"
    [ -n "$status" ] && line="$line status=$status"
    line="$line msg=\"$(printf '%s' "$msg" | tr -d '\r\n')\""
  fi
  # why: the terminal shows warnings and errors; the full trail goes to the log file
  [ "$(_qs_lvlnum "$level")" -ge "$(_qs_lvlnum "${QUALITY_LOG_CONSOLE:-WARN}")" ] && printf '%s\n' "$line" >&2
  if [ -n "${QUALITY_LOG_FILE:-}" ]; then
    mkdir -p "$(dirname "$QUALITY_LOG_FILE")" 2>/dev/null || true
    printf '%s\n' "$line" >> "$QUALITY_LOG_FILE" 2>/dev/null || true
  fi
}

# qs_result <comp> <file> <action> <SUCCESS|ERROR> [msg]
# The "did X on file Y: SUCCESS/ERROR" INFO line.
qs_result(){
  local comp="$1" file="$2" action="$3" status="$4" msg="${5:-}"
  local lvl=INFO; [ "$status" = "ERROR" ] && lvl=ERROR
  qs_log "$lvl" "$comp" "$msg" "$file" "$action" "$status"
}
