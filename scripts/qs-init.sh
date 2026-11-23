#!/usr/bin/env bash
# qs-init.sh - git iniciar: a new project ready to work: git init (branches main and develop), quality
# hooks and git aliases, base image, standard repository files, AI agent files (git ia) and their
# .gitignore block. Its only commit is the empty root commit of main; it prints the next steps.
#   git iniciar [folder] [--sin-ia] [--remoto <url>]
set -euo pipefail
# init_repository: makes the repository of the current folder: git init on main, an empty root
# commit ("chore: initial commit") on main, develop at that commit, HEAD on develop. Plumbing
# only (commit-tree, update-ref), so no hook runs and init.defaultBranch is never read or written.
# Arguments: none. Output: none. Errors: git's, which stop the script (set -e).
init_repository() {
	git init -q -b main
	# why: commit-tree needs an identity; a machine without one gets a placeholder for this commit
	if ! { git var GIT_AUTHOR_IDENT && git var GIT_COMMITTER_IDENT; } >/dev/null 2>&1; then
		export GIT_AUTHOR_NAME=cqs GIT_AUTHOR_EMAIL=cqs@localhost
		export GIT_COMMITTER_NAME=cqs GIT_COMMITTER_EMAIL=cqs@localhost
	fi
	local tree root
	# why: the empty tree, written by mktree from an empty list (the same hash in SHA-1 repositories)
	tree="$(git mktree </dev/null)"
	# why: --no-gpg-sign, a global commit.gpgsign must not prompt for a key on this commit
	root="$(git commit-tree --no-gpg-sign "$tree" -m "chore: initial commit")"
	git update-ref refs/heads/main "$root"
	git update-ref refs/heads/develop "$root"
	git symbolic-ref HEAD refs/heads/develop
}
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() {
	echo "[iniciar] $*" >&2
	exit 1
}
dest="" ai=1 remote=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--sin-ia | --no-ai) ai=0 ;;
	--remoto | --remote)
		[ "$#" -ge 2 ] || die "$1 needs a URL"
		remote="$2"
		shift
		;;
	-h | --help)
		bash "$SUITE/scripts/qs-help.sh" iniciar
		exit 0
		;;
	-*) die "unknown option '$1' (--sin-ia, --remoto <url>)" ;;
	*)
		[ -z "$dest" ] || die "one folder only"
		dest="$1"
		;;
	esac
	shift
done
# why: git runs aliases from the top of a repository; GIT_PREFIX is where you typed the command
cd "${GIT_PREFIX:-.}"
if [ -n "$dest" ]; then
	mkdir -p "$dest"
	cd "$dest"
fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	# why ask for the prefix: on Windows the toplevel is C:/x while the shell says /c/x
	[ -z "$(git rev-parse --show-prefix)" ] || die "this folder is inside the repository '$(git rev-parse --show-toplevel)'; choose a folder outside it"
	echo "[iniciar] already a git repository: setting it up"
else
	init_repository
	echo "[iniciar] git init: branches main and develop"
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
  3. $(git remote get-url origin >/dev/null 2>&1 && echo 'git push -u origin main develop' || echo 'git remote add origin <url> && git push -u origin main develop')
  4. git np 0.1.0 && git np 1          (version tree and the first work order)
  Manual: git ayuda   (one command: git ayuda np)
EON
