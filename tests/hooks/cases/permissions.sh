#!/usr/bin/env bash
# Case: Claude Code permission lists and OpenCode per-agent permission.bash (PM1, PM2).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# PM1: the lists of ai-template/.claude/settings.json match the permissions table.
python3 - "$SUITE/ai-template/.claude/settings.json" <<'PY' && ok "PM1 settings.json lists match the table" || fail "PM1 settings.json lists"
import json, sys
p = json.load(open(sys.argv[1]))["permissions"]
want = {
    "allow": ["checkpoint", "revision", "tests", "spike"],
    "ask": ["intentos", "testing", "cuarentena", "aceptar"],
    "deny": ["changelog --escribir", "migracion", "formatear", "elegir", "docs", "publicar", "combinar"],
}
for kind, cmds in want.items():
    for c in cmds:
        assert f"Bash(git {c}:*)" in p[kind], (kind, c)
assert "Bash(git changelog:*)" in p["allow"]
PY

# PM2: ai-sync.sh writes permission.bash per role.
R="$T/pm2"
mkdir -p "$R/.claude" "$R/.agents/skills/demo"
cp -R "$SUITE/ai-template/.claude/agents" "$R/.claude/agents"
echo '{}' >"$R/opencode.json"
bash "$SUITE/scripts/ai-sync.sh" "$R" >/dev/null
oc="$R/.opencode/agents"
has() { grep -qxF -- "    \"$2\": $3" "$oc/$1.md"; }
has systems-analyst "git aceptar*" allow && has systems-analyst "git intentos*" allow &&
	ok "PM2 lead allows aceptar and intentos" || fail "PM2 lead rows"
has developer "git aceptar*" deny && has developer "git intentos*" deny &&
	ok "PM2 developer denies aceptar and intentos" || fail "PM2 developer rows"
has developer "git checkpoint*" allow && has developer "git revision --aplicar*" allow &&
	ok "PM2 developer allows checkpoint and revision --aplicar" || fail "PM2 developer allow"
has qa "git tests*" allow && has reviewer "git revision*" allow &&
	has external-worker "git cuarentena*" allow && ok "PM2 qa, reviewer, external-worker rows" || fail "PM2 role rows"
for a in developer qa reviewer external-worker systems-analyst intern; do
	for c in "git release*" "git publicar*" "git combinar*" "git migracion*" "git push --no-verify*" "git push --force*" "git push -f*"; do
		has "$a" "$c" deny || fail "PM2 $a does not deny $c"
	done
done
ok "PM2 human-only commands denied to every role"

# PM3: git ia --actualizar merges settings.json: user rows and keys stay, suite rows are
# refreshed, rows the suite retired go away.
P="$T/pm3"
git init -q -b main "$P"
bash "$SUITE/scripts/ai-init.sh" "$P" >/dev/null 2>&1
python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.claude/settings.json"
d = json.load(open(p))
d["model"] = "opus"
d["permissions"]["allow"] += ["Bash(make test:*)", "Bash(git old-suite-row:*)"]
d["permissions"]["allow"].remove("Bash(git tests:*)")
d["permissions"]["deny"].append("Bash(rm -rf:*)")
json.dump(d, open(p, "w"))
# an older suite version shipped old-suite-row: record it as suite-owned
f = sys.argv[1] + "/.git/qs-settings-owned.json"
o = json.load(open(f))
o["permissions"]["allow"].append("Bash(git old-suite-row:*)")
json.dump(o, open(f, "w"))
PY
bash "$SUITE/scripts/ai-init.sh" --actualizar "$P" >/dev/null 2>&1
python3 - "$P/.claude/settings.json" <<'PY' && ok "PM3 --actualizar merges settings.json" || fail "PM3 merge"
import json, sys
d = json.load(open(sys.argv[1]))
a = d["permissions"]["allow"]
assert d["model"] == "opus"
assert "Bash(make test:*)" in a and "Bash(rm -rf:*)" in d["permissions"]["deny"]
assert "Bash(git old-suite-row:*)" not in a, "retired suite row stayed"
assert "Bash(git tests:*)" in a, "suite row not restored"
assert len(a) == len(set(a))
assert len(d["hooks"]["PostToolUse"]) == 1
PY
