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

# PM3 in a linked worktree (.git is a file): fresh `git ia` and --actualizar both work.
git -C "$P" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null \
	commit -q --allow-empty -m init || fail "PM3 fixture: commit"
git -C "$P" worktree add -q "$T/pm3wt" -b wt || fail "PM3 fixture: worktree add"
bash "$SUITE/scripts/ai-init.sh" "$T/pm3wt" >/dev/null 2>&1 && [ -f "$T/pm3wt/.claude/settings.json" ] &&
	bash "$SUITE/scripts/ai-init.sh" --actualizar "$T/pm3wt" >/dev/null 2>&1 &&
	ok "PM3 works in a linked worktree" || fail "PM3 worktree"

# PM3 reading: a BOM and // /* */ comments are accepted (BOM kept); invalid JSON only skips
# the settings step.
python3 - "$P/.claude/settings.json" <<'PY'
import sys
p = sys.argv[1]
open(p, "w", encoding="utf-8").write(
    '\ufeff// mine\n{"model": "x", /* c */ "permissions": {"allow": ["Bash(a://b:*)"]}}\n')
PY
bash "$SUITE/scripts/ai-init.sh" --actualizar "$P" >/dev/null 2>&1
head -c 3 "$P/.claude/settings.json" | od -An -tx1 | grep -q 'ef bb bf' && ok "PM3 BOM kept" || fail "PM3 BOM lost"
python3 - "$P/.claude/settings.json" <<'PY' && ok "PM3 comments accepted, rows kept" || fail "PM3 comments"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8-sig").read())
assert d["model"] == "x" and "Bash(a://b:*)" in d["permissions"]["allow"]
assert "Bash(git tests:*)" in d["permissions"]["allow"]
PY
printf '{ broken' >"$P/.claude/settings.json"
bash "$SUITE/scripts/ai-init.sh" --actualizar "$P" >/dev/null 2>&1 &&
	[ "$(cat "$P/.claude/settings.json")" = "{ broken" ] && [ -f "$P/AGENTS.md" ] &&
	ok "PM3 invalid JSON skips only the settings step" || fail "PM3 invalid JSON"

# PM3 rows: a retired suite row that the user also had is kept (a deny row always); no
# duplicates.
python3 - "$SUITE/scripts/settings-merge.py" <<'PY' && ok "PM3 row ownership and dedupe" || fail "PM3 ownership"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sm", sys.argv[1])
sm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sm)
tpl = {"permissions": {"allow": ["A"], "deny": ["D"]}}
# the user had A and D before the suite shipped them: not owned
r, mine = sm.merge(tpl, {"permissions": {"allow": ["A", "A", "U"], "deny": ["D"]}}, {})
assert r["permissions"]["allow"] == ["A", "U"] and mine["permissions"] == {}
# the suite later retires A and D: the user's A and D stay
r, _ = sm.merge({"permissions": {}}, r, mine)
assert r["permissions"]["allow"] == ["A", "U"] and r["permissions"]["deny"] == ["D"]
# a row the suite added is dropped when retired, but a deny row never
r, mine = sm.merge(tpl, {}, {})
assert mine["permissions"] == {"allow": ["A"], "deny": ["D"]}
r, _ = sm.merge({"permissions": {}}, r, mine)
assert "allow" not in r["permissions"] and r["permissions"]["deny"] == ["D"]
PY
