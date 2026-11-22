#!/usr/bin/env bash
# setup-global.sh - one-time global git setup for the suite. Run once per machine.
#   ./git-integration/setup-global.sh [--on-clone] [suite-dir]
#
# Always:
#   git clonar <url> [dest]   global alias: clone + bootstrap in one step
#   git iniciar [folder]      a new project: git init (main and develop) + hooks + repository files + AI files
#   git instalar [repo]       an existing clone: hooks, aliases, tools, repository files
#   git ia [--actualizar]     AI agent files (out of the repository via .gitignore)
#   git ayuda [command]       the manual of every git command (docs/GIT-COMMANDS.md)
#   git actualizar-suite      clean update after unzipping a new suite version
#   QS_SUITE                  environment variable with the suite folder (~/.bashrc; on Windows
#                             also for PowerShell/cmd with setx). QS_NO_PROFILE=1 skips it.
#   init.templateDir          every new clone/init self-installs the suite on its first commit
# With --on-clone:
#   a template post-checkout that, right after `git clone`, asks whether to bootstrap
set -euo pipefail
ON_CLONE=0
if [ "${1:-}" = "--on-clone" ]; then
	ON_CLONE=1
	shift
fi
SUITE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TPL="${CQS_TEMPLATE_DIR:-$HOME/.config/git/cqs-template}"

# why: a global alias works outside any repository (repo-local aliases do not exist before
# the clone). GIT_PREFIX keeps the folder you ran it from as the clone destination base.
git config --global alias.clonar "!f() { cd \"\${GIT_PREFIX:-.}\" && bash \"${SUITE_DIR}/bootstrap.sh\" \"\$@\"; }; f"
# why: one command to update the suite on this machine (clean image, every repository re-pointed)
git config --global alias.actualizar-suite "!bash \"${SUITE_DIR}/scripts/qs-update.sh\""
git config --global alias.iniciar "!bash \"${SUITE_DIR}/scripts/qs-init.sh\""
git config --global alias.instalar "!f() { cd \"\${GIT_PREFIX:-.}\" && bash \"${SUITE_DIR}/bootstrap.sh\" \"\${1:-.}\"; }; f"
git config --global alias.ia "!f() { cd \"\${GIT_PREFIX:-.}\" && bash \"${SUITE_DIR}/scripts/ai-init.sh\" \"\$@\"; }; f"
git config --global alias.ayuda "!bash \"${SUITE_DIR}/scripts/qs-help.sh\""

# why: scripts, agents and other shells find the suite without typing its path
if [ "${QS_NO_PROFILE:-0}" != 1 ]; then
	rc="$HOME/.bashrc"
	touch "$rc"
	sed -i.bak '/# code-quality-suite (setup-global.sh)$/d' "$rc" && rm -f "$rc.bak"
	printf 'export QS_SUITE="%s"   # code-quality-suite (setup-global.sh)\n' "$SUITE_DIR" >>"$rc"
	if command -v setx >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		setx QS_SUITE "$(cygpath -w "$SUITE_DIR")" >/dev/null 2>&1 && QS_SETX=1
	fi
fi

mkdir -p "$TPL/hooks"
bake() {
	sed "s|__CQS_SUITE_DIR__|${SUITE_DIR//|/\\|}|g" "$1" >"$2"
	chmod +x "$2"
}
for h in pre-commit pre-push; do bake "$SUITE_DIR/git-integration/cqs-autoinstall" "$TPL/hooks/$h"; done
if [ "$ON_CLONE" = 1 ]; then
	bake "$SUITE_DIR/git-integration/cqs-onclone" "$TPL/hooks/post-checkout"
else
	rm -f "$TPL/hooks/post-checkout"
fi
git config --global init.templateDir "$TPL"

echo "[cqs] Suite: $SUITE_DIR"
echo "[cqs] Alias:  git iniciar [folder]      (new project: git init + hooks + files + AI files)"
echo "[cqs] Alias:  git clonar <url> [dest]   (clone + set up)"
echo "[cqs] Alias:  git instalar [repo]       (set up a clone you already have)"
echo "[cqs] Alias:  git ia [--actualizar]     (AI agent files, kept out of the repository)"
echo "[cqs] Alias:  git ayuda [command]       (manual of every git command)"
echo "[cqs] Alias:  git actualizar-suite      (after unzipping a new suite version: clean update)"
[ "${QS_NO_PROFILE:-0}" = 1 ] || echo "[cqs] QS_SUITE=$SUITE_DIR  (~/.bashrc$([ "${QS_SETX:-0}" = 1 ] && echo ' and Windows user environment'); open a new terminal)"
echo "[cqs] init.templateDir = $TPL  (new clones self-install on the first commit)"
[ "$ON_CLONE" = 1 ] && echo "[cqs] On clone: plain 'git clone' asks whether to bootstrap right away"
echo "[cqs] Existing repos: cd <repo> && git instalar   (manual: git ayuda)"
