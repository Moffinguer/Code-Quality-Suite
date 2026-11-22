#!/usr/bin/env bash
# Cases of QUARANTINE (6.0.0 quarantine_branch task): git cuarentena, --borrar and git aceptar.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

N=6.0.0/ot1
ORIG=$N/ORIGINAL
TASK=$N/a
Q=$N/QUARANTINE-a

# refused WORD CMD...: the command must fail and print WORD.
# Arguments: $1 text expected in the output, then the command. Returns: 0 or fails the case.
refused() {
	local word="$1" out
	shift
	if out="$("$@" 2>&1)"; then fail "not refused: $*"; fi
	grep -q -- "$word" <<<"$out" || fail "refused without '$word': $* -> $out"
}

# --- fixture: an ORIGINAL with a file and a task branch with one commit
git checkout -q -b "$ORIG" develop
printf 'base\n' >shared.txt
git add shared.txt
git commit -q -m "chore: shared file"
git checkout -q -b "$TASK" "$ORIG"
printf 'a\n' >a.txt
git add a.txt
git commit -q -m "feat: a"
git branch "$N/b" "$ORIG"
git checkout -q "$ORIG"

# --- QR1: creation from the ORIGINAL of the task, checked out
refused "no such branch" git cuarentena "$N/zzz"
refused "special branch" git cuarentena "$N/REVIEW-a"
refused "ORIGINAL" git cuarentena "$ORIG"
git cuarentena "$TASK" >/dev/null || fail "QR1: cuarentena failed"
[ "$(git branch --show-current)" = "$Q" ] && ok "QR1 quarantine created and checked out" || fail "QR1: not on $Q"
[ "$(git rev-parse "$Q")" = "$(git rev-parse "$ORIG")" ] && ok "QR1 starts at the ORIGINAL" || fail "QR1: base"
git checkout -q "$ORIG"
refused "already exists" git cuarentena "$TASK"
ok "QR1 second creation refused"

# --- QR2: aceptar
g1="$(plumb_commit local "$Q" gen1.txt one $'feat: gen one\n\nGenerated-by: some-model')"
g2="$(plumb_commit local "$Q" gen2.txt two $'feat: gen two\n\nGenerated-by: some-model')"
git checkout -q "$ORIG"
other="$(git rev-parse "$TASK")"
refused "unknown commit" git aceptar deadbeefdead --a "$TASK"
refused "not a commit of" git aceptar "$other" --a "$TASK"
refused "no such branch" git aceptar "$g1" --a "$N/zzz"
refused "no quarantine" git aceptar "$g1" --a "$N/b"
[ "$(git rev-parse "$TASK")" = "$other" ] && ok "QR2 refusals leave the task alone" || fail "QR2: task moved"
git aceptar "$g1" --a "$TASK" >/dev/null || fail "QR2: aceptar failed"
[ "$(git branch --show-current)" = "$ORIG" ] && ok "QR2 checkout restored" || fail "QR2: branch changed"
[ "$(git rev-list --count "$other..$TASK")" = 1 ] && ok "QR2 one commit created" || fail "QR2: count"
body="$(git log -n1 --format=%B "$TASK")"
grep -q '^Reviewed-by: tester <t@example.com>$' <<<"$body" && ok "QR2 Reviewed-by" || fail "QR2: trailer: $body"
grep -q '^Generated-by: some-model$' <<<"$body" && ok "QR2 Generated-by kept" || fail "QR2: generated-by: $body"
[ "$(git show "$TASK:gen1.txt")" = one ] && ok "QR2 content taken" || fail "QR2: content"
git show "$TASK:gen2.txt" >/dev/null 2>&1 && fail "QR2: second commit came too"
git aceptar "$g2" --a "$TASK" >/dev/null || fail "QR2: second aceptar failed"
[ "$(git rev-list --count "$other..$TASK")" = 2 ] && ok "QR2 second commit taken" || fail "QR2: second count"

# --- QR3: a regulated repository refuses both commands
cp .quality-rules.json "$T/rules.bak"
python3 - <<'PY'
import json
p = ".quality-rules.json"
d = json.load(open(p))
d["data_class"] = "regulated"
json.dump(d, open(p, "w"), indent=2)
PY
refused "public or invented code" git cuarentena "$TASK"
refused "public or invented code" git aceptar "$g1" --a "$TASK"
cp "$T/rules.bak" .quality-rules.json
ok "QR3 regulated refused"

# --- QR4: --borrar
git checkout -q "$Q"
refused "checked out" git cuarentena --borrar "$TASK" --yes
git checkout -q "$ORIG"
tip="$(git rev-parse "$Q")"
out="$(git cuarentena --borrar "$TASK" --yes 2>&1)" || fail "QR4: borrar failed: $out"
grep -q "$tip" <<<"$out" && ok "QR4 tip printed" || fail "QR4: no tip: $out"
git show-ref --verify -q "refs/heads/$Q" && fail "QR4: branch left"
ok "QR4 quarantine deleted"
