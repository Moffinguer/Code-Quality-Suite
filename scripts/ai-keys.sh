#!/usr/bin/env bash
# ai-keys.sh - which provider keys of ai-stack/.env work, and which model answers each role.
# Sends one tiny request (max 5 tokens) to every model of the gateway and to every role, and
# prints a table with the reason of each failure (no key, key rejected, quota, model renamed...).
#   ai-keys.sh [--env <path to .env>] [--providers | --roles]
# Needs the gateway running (cd ai-stack && docker compose up -d). Uses LITELLM_MASTER_KEY.
set -euo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVF="$SUITE/ai-stack/.env" WHAT=all
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env) ENVF="${2:?--env needs a file}"; shift ;;
    --providers) WHAT=providers ;;
    --roles) WHAT=roles ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[ai-keys] unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$ENVF" ] || { echo "[ai-keys] no $ENVF (cp ai-stack/.env.example ai-stack/.env and fill it)" >&2; exit 1; }
# why run it: on Windows "python3" may be the Microsoft Store stub, which exists but does not work
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  for c in python3 python py; do "$c" -c 'import sys' >/dev/null 2>&1 && { PY="$c"; break; }; done
fi
[ -n "$PY" ] || { echo "[ai-keys] Python 3 not found (install it or set PYTHON=...)" >&2; exit 1; }
QS_GATEWAY_URL="${QS_GATEWAY_URL:-http://localhost:4000}" "$PY" - "$ENVF" "$WHAT" <<'PY'
import collections, json, os, re, sys, time, urllib.request, urllib.error

envf, what = sys.argv[1], sys.argv[2]
env = {}
for line in open(envf, encoding="utf-8"):
    m = re.match(r"\s*([A-Z0-9_]+)=(.*)$", line)
    if m:
        env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
master = env.get("LITELLM_MASTER_KEY", "")
url = os.environ["QS_GATEWAY_URL"].rstrip("/")
# provider prefix of a deployment -> the .env key it needs
KEY = {"anthropic": "ANTHROPIC_API_KEY", "groq": "GROQ_API_KEY", "cerebras": "CEREBRAS_API_KEY",
       "gemini": "GEMINI_API_KEY", "openrouter": "OPENROUTER_API_KEY", "deepseek": "DEEPSEEK_API_KEY",
       "nvidia_nim": "NVIDIA_NIM_API_KEY", "sambanova": "SAMBANOVA_API_KEY", "mistral": "MISTRAL_API_KEY",
       "codestral": "CODESTRAL_API_KEY", "cohere_chat": "COHERE_API_KEY", "cohere": "COHERE_API_KEY",
       "github": "GITHUB_API_KEY", "huggingface": "HUGGINGFACE_API_KEY", "cloudflare": "CLOUDFLARE_API_KEY",
       "openai": None, "ollama_chat": None}


def call(path, body=None, timeout=60):
    req = urllib.request.Request(url + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + master, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except ValueError:
            return e.code, {}
    except OSError as e:
        return 0, {"error": {"message": str(e)}}


def reason(code, data):
    msg = str((data.get("error") or {}).get("message", data)) if isinstance(data, dict) else str(data)
    low = msg.lower()
    if code in (401, 403) or re.search(r"exception - 40[13]\b", low) or "api key" in low \
            or "unauthorized" in low or "authentication" in low or "permission" in low:
        return "key rejected (check it in .env)"
    if code == 402 or "insufficient balance" in low or "credit" in low:
        return "no balance / credits"
    if code == 429 or "rate limit" in low or "quota" in low or "exhausted" in low:
        return "quota or rate limit (try later)"
    if code == 404 or "not found" in low or "does not exist" in low or "decommissioned" in low:
        return "model not found: renamed? (providers.yaml)"
    if "ollama" in low and ("connect" in low or "refused" in low or "resolve" in low):
        return "Ollama not running (docker compose --profile local up -d)"
    if code == 0:
        return "gateway not reachable: " + msg[:60]
    if "connection error" in low or "timed out" in low or "timeout" in low:
        return "provider not reachable (network or proxy)"
    return f"HTTP {code}: " + re.sub(r"\s+", " ", msg)[:70]


code, info = call("/model/info")
if code != 200:
    sys.exit(f"[ai-keys] cannot read {url}/model/info ({reason(code, info)}). Is the gateway up? "
             "cd ai-stack && docker compose up -d")
# why the id count: the gateway expands every "provider/*" route into that provider's whole catalog,
# all sharing the route's id; the models of providers.yaml and the roles have an id of their own
data = info.get("data", [])
ids = collections.Counter((d.get("model_info") or {}).get("id") for d in data)
deps = [(d["model_name"], d.get("litellm_params", {}).get("model", "")) for d in data
        if "*" not in d["model_name"] and ids[(d.get("model_info") or {}).get("id")] == 1]
ask = {"messages": [{"role": "user", "content": "Reply with the word OK."}], "max_tokens": 5,
       "timeout": 30, "num_retries": 0}
print(f"Gateway {url}, config: {env.get('LITELLM_CONFIG', 'config.yaml')}")
working = 0
if what in ("all", "providers"):
    print(f"\n{'model':<22} {'provider model':<38} result")
    for name, model in deps:
        if "*" in name or name.startswith("role-"):
            continue
        var = KEY.get(model.split("/")[0], "")
        if var and not env.get(var):
            print(f"{name:<22} {model:<38} -- no key ({var} empty)")
            continue
        if var is None and name in ("free-pool",) and not env.get("FREELLMAPI_KEY"):
            print(f"{name:<22} {model:<38} -- not configured (profile free)")
            continue
        t = time.time()
        c, d = call("/v1/chat/completions", dict(ask, model=name))
        if c == 200:
            working += 1
            print(f"{name:<22} {model:<38} OK   {time.time() - t:.1f}s")
        else:
            print(f"{name:<22} {model:<38} FAIL {reason(c, d)}")
if what in ("all", "roles"):
    print(f"\n{'role':<14} answered by")
    roles = sorted({n for n, _ in deps if n.startswith("role-")})
    for role in roles:
        c, d = call("/v1/chat/completions", dict(ask, model=role, timeout=20), timeout=400)
        print(f"{role:<14} " + (d.get("model", "?") if c == 200 else "FAIL " + reason(c, d)))
if what in ("all", "providers"):
    print(f"\n{working} model(s) answering. Keys: docs/AI-DEMO.md. Empty ones are simply skipped.")
PY
