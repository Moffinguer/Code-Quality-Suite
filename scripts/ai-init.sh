#!/usr/bin/env bash
# ai-init.sh - git ia: add the AI working files to a repository: AGENTS.md (+ CLAUDE.md, GEMINI.md),
# shared skills (with the manual of the git commands), Claude Code and OpenCode subagents, the
# quality-gate hook, and the knowledge map. <SUITE> becomes this suite's path.
#   ai-init.sh [--actualizar] [repo]
# The files stay OUT of the repository: a managed .gitignore block lists them (and the personal
# .quality-rules.json), and any of them already committed is taken out of the index (the files
# stay on disk; commit afterwards). Existing files are kept; --actualizar rewrites the suite's own
# files (skills, subagents), merges its rows into .claude/settings.json (yours stay), but never AGENTS.md, CLAUDE.md, GEMINI.md, opencode.json or
# knowledge/ or dev_documents/, which are yours (the dev_documents/ templates are added only when missing).
set -euo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
update=0 target=""
for a in "$@"; do
	case "$a" in
	--actualizar | --update) update=1 ;;
	-h | --help)
		sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		echo "[ia] unknown option '$a' (--actualizar)" >&2
		exit 2
		;;
	*) target="$a" ;;
	esac
done
repo="$(cd "${target:-.}" && git rev-parse --show-toplevel)"
tpl="$SUITE/ai-template"
added=0 kept=0 updated=0
# yours - tell whether a template file belongs to the project (never rewritten by --actualizar).
# Arguments: $1 path relative to the template root. Returns 0 when it is the project's own file.
yours() {
	case "$1" in AGENTS.md | CLAUDE.md | GEMINI.md | opencode.json | knowledge/* | dev_documents/*) return 0 ;; esac
	return 1
}
while IFS= read -r -d '' f; do
	rel="${f#"$tpl"/}"
	dst="$repo/$rel"
	if [ -e "$dst" ]; then
		if [ "$update" = 1 ] && [ "$rel" = ".claude/settings.json" ]; then
			# why: the project's own rows and keys stay; only the suite's rows are refreshed
			sed "s|<SUITE>|${SUITE//|/\\|}|g" "$f" >"$repo/.git/qs-settings-template.json"
			before="$(cat "$dst")"
			python3 "$SUITE/scripts/settings-merge.py" "$repo/.git/qs-settings-template.json" "$dst" \
				"$repo/.git/qs-settings-owned.json"
			rm -f "$repo/.git/qs-settings-template.json"
			[ "$before" = "$(cat "$dst")" ] || updated=$((updated + 1))
		elif [ "$update" = 1 ] && ! yours "$rel"; then
			new="$(sed "s|<SUITE>|${SUITE//|/\\|}|g" "$f")"
			if [ "$new" != "$(cat "$dst")" ]; then
				printf '%s\n' "$new" >"$dst"
				updated=$((updated + 1))
			fi
		else
			kept=$((kept + 1))
			[ "$update" = 1 ] || echo "[ia] kept existing $rel"
		fi
		continue
	fi
	mkdir -p "$(dirname "$dst")"
	sed "s|<SUITE>|${SUITE//|/\\|}|g" "$f" >"$dst"
	# why: remember which rows the suite installed, so a later --actualizar can retire them
	[ "$rel" != ".claude/settings.json" ] ||
		python3 "$SUITE/scripts/settings-merge.py" "$dst" "$dst" "$repo/.git/qs-settings-owned.json"
	added=$((added + 1))
done < <(find "$tpl" -type f -print0)

# the manual of the git commands, as a skill: always the one of this suite version
skill="$repo/.agents/skills/git-commands/SKILL.md"
mkdir -p "$(dirname "$skill")"
{
	printf -- '---\nname: git-commands\n'
	printf 'description: Manual of every git command of this repository (np, nr, nv, es, subir, integra, arbol, changelog, release, publicar, combinar, encoding, repo-files, iniciar, instalar, ia, ayuda): syntax, when to use each and who runs it. Read it before running any git command here.\n---\n\n'
	sed -e 's/ *<!--[^>]*-->//g' "$SUITE/docs/GIT-COMMANDS.md"
} >"$skill.tmp"
mv "$skill.tmp" "$skill"
bash "$SUITE/scripts/ai-sync.sh" "$repo"

# .gitignore: one managed block (rewritten every time); the older single lines it covers go away
gi="$repo/.gitignore"
touch "$gi"
awk '
  /^# >>> code-quality-suite/ { skip = 1; next }
  /^# <<< code-quality-suite/ { skip = 0; next }
  skip { next }
  $0 == "/.claude/settings.local.json" || $0 == "/.claude/agent-memory-local/" || $0 == "/.claude/worktrees/" \
    || $0 == "/.opencode/node_modules/" || $0 == "/.opencode/package-lock.json" { next }
  { print }' "$gi" >"$gi.tmp"
# why: these files are personal tooling (agents, prompts, local rules), not part of the product
IGNORED=(/AGENTS.md /CLAUDE.md /GEMINI.md /opencode.json /.agents/ /.claude/ /.gemini/ /.opencode/ /knowledge/ /.quality-rules.json
	'/docs/[0-9]*/' /dev_documents/)
{
	cat "$gi.tmp"
	[ -s "$gi.tmp" ] && [ -n "$(tail -c1 "$gi.tmp")" ] && echo
	echo "# >>> code-quality-suite: AI agent files and local rules stay out of the repository (git ia)"
	printf '%s\n' "${IGNORED[@]}"
	echo "# <<< code-quality-suite"
} >"$gi"
rm -f "$gi.tmp"

# files of that list committed before: out of the index, kept on disk
# why: IGNORED holds literal gitignore patterns (the shell never expands them); the loop turns each
# into a git pathspec, and a glob entry needs a trailing "*" there ("*" also crosses "/")
SPECS=()
for e in "${IGNORED[@]}"; do
	case "$e" in *"["*) SPECS+=(":$e*") ;; *) SPECS+=(":$e") ;; esac
done
tracked="$(git -C "$repo" ls-files -- "${SPECS[@]}" | wc -l | tr -d ' ')"
if [ "$tracked" -gt 0 ]; then
	git -C "$repo" rm -r -q --cached --ignore-unmatch -- "${SPECS[@]}"
	git -C "$repo" add .gitignore
	echo "[ia] $tracked AI/local file(s) were committed: taken out of the index (still on disk)."
	echo '     Commit it: git commit -m "chore: keep AI agent files out of the repo"'
fi
if [ "$update" = 1 ]; then
	echo "[ia] $updated file(s) updated, $added added; AGENTS.md, CLAUDE.md, opencode.json, knowledge/ and dev_documents/ untouched."
else echo "[ia] $added file(s) added, $kept kept. Next: fill the Project section of AGENTS.md (git ayuda ia)."; fi
