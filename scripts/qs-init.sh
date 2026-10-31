#!/usr/bin/env bash
# qs-init.sh - git iniciar: a new project ready to work: git init (branch develop), quality hooks
# and git aliases, base image, standard repository files, AI agent files (git ia) and their
# .gitignore block. It does not commit; it prints the next steps.
#   git iniciar [folder] [--sin-ia] [--remoto <url>]
set -euo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() { echo "[iniciar] $*" >&2; exit 1; }
dest="" ai=1 remote=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sin-ia|--no-ai) ai=0 ;;
    --remoto|--remote) [ "$#" -ge 2 ] || die "$1 needs a URL"; remote="$2"; shift ;;
    -h|--help) bash "$SUITE/scripts/qs-help.sh" iniciar; exit 0 ;;
    -*) die "unknown option '$1' (--sin-ia, --remoto <url>)" ;;
    *) [ -z "$dest" ] || die "one folder only"; dest="$1" ;;
  esac
  shift
done
# why: git runs aliases from the top of a repository; GIT_PREFIX is where you typed the command
cd "${GIT_PREFIX:-.}"
if [ -n "$dest" ]; then mkdir -p "$dest"; cd "$dest"; fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # why ask for the prefix: on Windows the toplevel is C:/x while the shell says /c/x
  [ -z "$(git rev-parse --show-prefix)" ] || die "this folder is inside the repository '$(git rev-parse --show-toplevel)'; choose a folder outside it"
  echo "[iniciar] already a git repository: setting it up"
else
  git init -q -b develop
  echo "[iniciar] git init: branch develop"
fi
if [ -n "$remote" ]; then
  if git remote get-url origin >/dev/null 2>&1; then git remote set-url origin "$remote"; else git remote add origin "$remote"; fi
  echo "[iniciar] origin: $remote"
fi
bash "$SUITE/bootstrap.sh" "$PWD"
[ "$ai" = 1 ] && bash "$SUITE/scripts/ai-init.sh" "$PWD"
cat <<EON

[iniciar] Ready. Next:
$([ "$ai" = 1 ] && echo "  1. Fill the Project section of AGENTS.md (name, data class, stack, build and test commands)")
  2. git add -A && git commit -m "chore: initial project skeleton"    (the first commit installs the tools)
  3. $(git remote get-url origin >/dev/null 2>&1 && echo 'git push -u origin develop' || echo 'git remote add origin <url> && git push -u origin develop')
  4. git np 0.1.0 && git np 1          (version tree and the first work order)
  Manual: git ayuda   (one command: git ayuda np)
EON
