#!/usr/bin/env bash
# ai-ask.sh - one prompt to a role alias of the local model gateway (LiteLLM, OpenAI API).
#   ai-ask.sh <alias> "<prompt>" [--file path]...     e.g. ai-ask.sh role-intern "Summarise..."
# Env: QS_GATEWAY_URL (default http://localhost:4000), QS_GATEWAY_KEY (a LiteLLM virtual key).
# The alias decides the model and its fallbacks (ai-stack/litellm/config.yaml); data rules:
# role-local never leaves this machine.
set -euo pipefail
alias_="${1:?usage: ai-ask.sh <alias> \"<prompt>\" [--file path]...}"; prompt="${2:?prompt missing}"; shift 2
# why run it: on Windows "python3" may be the Microsoft Store stub, which exists but does not work
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  for c in python3 python py; do "$c" -c 'import sys' >/dev/null 2>&1 && { PY="$c"; break; }; done
fi
[ -n "$PY" ] || { echo "[ai-ask] Python 3 not found (install it or set PYTHON=/path/to/python)" >&2; exit 1; }
files=()
while [ "$#" -gt 0 ]; do
  case "$1" in --file) files+=("$2"); shift 2 ;; *) shift ;; esac
done
url="${QS_GATEWAY_URL:-http://localhost:4000}/v1/chat/completions"
body="$(ALIAS="$alias_" PROMPT="$prompt" "$PY" -c '
import json, os, sys
msg = os.environ["PROMPT"]
for f in sys.argv[1:]:
    msg += "\n\n--- %s ---\n%s" % (f, open(f, encoding="utf-8", errors="replace").read())
print(json.dumps({"model": os.environ["ALIAS"], "messages": [{"role": "user", "content": msg}]}))' ${files[@]+"${files[@]}"})"
resp="$(curl -sS --fail-with-body -H "Authorization: Bearer ${QS_GATEWAY_KEY:?set QS_GATEWAY_KEY}" \
  -H "Content-Type: application/json" -d "$body" "$url")" || { echo "$resp" >&2; exit 1; }
printf '%s' "$resp" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print(d["choices"][0]["message"]["content"])
print("\n[model: %s]" % d.get("model", "?"), file=sys.stderr)'
