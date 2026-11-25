#!/usr/bin/env bash
# rama/repofiles.sh - git repo-files (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

cmd_repo_files() { # create the missing standard repository files (README, CHANGELOG, VERSION...)
	local root
	root="$(git rev-parse --show-toplevel)"
	# why: the option loop above already took --force
	if [ "$FORCE" = 1 ]; then set -- --force "$@"; fi
	engine "$root" repo-files "$@" || die "the suite image could not run (Docker?)"
}
