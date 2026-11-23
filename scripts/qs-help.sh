#!/usr/bin/env bash
# qs-help.sh - git ayuda [command]: the manual of the git commands (docs/GIT-COMMANDS.md), or the
# section of one command.
set -euo pipefail
DOC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/GIT-COMMANDS.md"
clean() { sed -e 's/ *<!--[^>]*-->//g'; }
[ "$#" -gt 0 ] || {
	clean <"$DOC"
	exit 0
}
cmd="${1#git }"
case "$cmd" in
nueva-padre) cmd=np ;; nueva-final) cmd=nr ;; ficheros-repo) cmd=repo-files ;;
publish) cmd=publicar ;; combine) cmd=combinar ;; clone) cmd=clonar ;;
known-bug) cmd=bug-conocido ;;
esac
out="$(awk -v c="git $cmd" '
  /^##/ && on { exit }   # why not #{2,3}: mawk has no intervals
  /^### / { h = substr($0, 5); n = split(h, p, " / "); for (i = 1; i <= n; i++) if (p[i] == c) on = 1 }
  on { print }' "$DOC" | clean)"
if [ -z "$out" ]; then
	echo "git ayuda: no command '$cmd'. Commands:" >&2
	grep '^### ' "$DOC" | sed 's/^### /  /' >&2
	exit 1
fi
printf '%s\n' "$out"
