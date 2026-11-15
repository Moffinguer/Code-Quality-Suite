#!/usr/bin/env bash
# Case: the branch flow in each agent's context (AF1-AF7).
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

A="$SUITE/ai-template/.claude/agents"
S="$SUITE/ai-template/.agents/skills"

# line FILE LABEL: print the single `- LABEL:` line of FILE; fail unless there is exactly one.
line() {
	[ "$(grep -c "^- $2:" "$1")" = 1 ] || fail "AF1 $1 needs exactly one '- $2:' line"
	grep "^- $2:" "$1"
}

# AF1/AF2: the four lines in each of the 7 agents, the human-only line, and the matrix content.
for r in systems-analyst developer qa reviewer docs-writer intern external-worker; do
	grep -qx '## Branches' "$A/$r.md" || fail "AF1 $r has no ## Branches"
	for l in Create "Work on" Integrate Push; do line "$A/$r.md" "$l" >/dev/null; done
	grep -q 'human only' "$A/$r.md" && grep -F 'git release' "$A/$r.md" | grep -q 'git publicar' &&
		grep -F 'git release' "$A/$r.md" | grep -q 'git combinar' || fail "AF2 $r"
done
ok "AF1 AF2 Branches section and human-only line in 7 agents"
line "$A/developer.md" Create | grep -q CHECKPOINT && ! line "$A/developer.md" Create | grep -q 'git np\|REVIEW\|TESTS' &&
	line "$A/developer.md" Integrate | grep -q '^- Integrate: never' && ok "AF1 developer" || fail "AF1 developer"
line "$A/qa.md" Create | grep -q TESTS && line "$A/qa.md" Create | grep -q REVIEW &&
	line "$A/qa.md" Integrate | grep -q bugfix && ok "AF1 qa" || fail "AF1 qa"
line "$A/reviewer.md" Create | grep -q REVIEW && ok "AF1 reviewer" || fail "AF1 reviewer"
line "$A/external-worker.md" Create | grep -q QUARANTINE &&
	line "$A/external-worker.md" Create | grep -q regulated && ok "AF1 external-worker" || fail "AF1 external-worker"
line "$A/systems-analyst.md" Create | grep -q 'git es' &&
	line "$A/systems-analyst.md" Integrate | grep -q "human's OK" && ok "AF1 systems-analyst" || fail "AF1 systems-analyst"

# AF3: tools.
grep -q '^tools:.*Write, Edit' "$A/reviewer.md" && grep -q '^tools:.*Bash' "$A/docs-writer.md" &&
	ok "AF3 reviewer edits, docs-writer has Bash" || fail "AF3 tools"

# AF4: the two skills.
for s in branch-workflow team-flow; do
	[ "$(wc -l <"$S/$s/SKILL.md")" -le 80 ] || fail "AF4 $s is longer than 80 lines"
	for w in squash 'Commits:' 'Files:' 'OT RELEASE' 'version RELEASE' TESTING limpiar-unmerged \
		publish_on_create MIGRATION DOCS REFACTOR FORMAT TESTS SPIKE ATTEMPT REVIEW QUARANTINE CHECKPOINT \
		'never pushed' 'human only'; do
		grep -qF -- "$w" "$S/$s/SKILL.md" || fail "AF4 $s lacks '$w'"
	done
	grep -q 'git-commands' "$S/$s/SKILL.md" && grep -q 'git ayuda' "$S/$s/SKILL.md" || fail "AF4 $s pointer"
done
ok "AF4 skills: at most 80 lines, required terms"

# AF5: a Who: line in every command section; human-only ones say so.
sections="$(awk '/^## 4\./{on=1} /^## 9\./{on=0} on' "$SUITE/docs/GIT-COMMANDS.md")"
missing="$(printf '%s\n' "$sections" | awk '/^### /{ if (h && !w) print h; h=$0; w=0 } /\*\*Who:\*\*/{ w=1 } END{ if (h && !w) print h }')"
[ -z "$missing" ] && ok "AF5 every command section has a Who: line" || fail "AF5 no Who: in: $missing"
for c in release publicar combinar; do
	printf '%s\n' "$sections" | awk -v c="### git $c" '$0==c{on=1;next} /^### /{on=0} on && /\*\*Who:\*\*/' | grep -q 'human only' ||
		fail "AF5 git $c is not human only"
done
ok "AF5 release, publicar, combinar say human only"

# AF6: OpenCode copies keep the role rows and the sections.
R="$T/af6"
mkdir -p "$R/.claude" "$R/.agents/skills/demo"
cp -R "$A" "$R/.claude/agents"
echo '{}' >"$R/opencode.json"
bash "$SUITE/scripts/ai-sync.sh" "$R" >/dev/null
oc="$R/.opencode/agents"
has() { grep -qxF -- "    \"$2\": $3" "$oc/$1.md"; }
for r in systems-analyst developer qa reviewer docs-writer intern external-worker; do
	grep -qx '## Branches' "$oc/$r.md" || fail "AF6 $r copy lacks Branches"
done
! grep -q 'edit: deny' "$oc/reviewer.md" && ! grep -q 'shell: deny' "$oc/docs-writer.md" || fail "AF6 deny edit/shell"
for c in "git integra*" "git np*" "git nr*" "git convertir-padre*" "git push*"; do has developer "$c" deny || fail "AF6 developer $c"; done
has developer "git checkpoint*" allow && has qa "git tests*" allow && has reviewer "git revision*" allow &&
	has external-worker "git cuarentena*" allow || fail "AF6 allow rows"
for c in "git es*" "git np*" "git nr*" "git integra*"; do has systems-analyst "$c" allow || fail "AF6 analyst $c"; done
for r in developer qa reviewer docs-writer intern external-worker systems-analyst; do
	for c in "git release*" "git publicar*" "git combinar*" "git push --no-verify*"; do has "$r" "$c" deny || fail "AF6 $r $c"; done
done
ok "AF6 OpenCode copies: sections and permission.bash"

# AF7: templates.
! grep 'systems-analyst |' "$SUITE/ai-template/AGENTS.md" | grep -q 'creates branches' &&
	! grep -q 'only on a branch NOT on origin' "$SUITE/ai-template/CLAUDE.md" && ok "AF7 role rows" || fail "AF7"
