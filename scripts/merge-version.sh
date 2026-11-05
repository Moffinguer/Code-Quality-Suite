#!/usr/bin/env bash
# merge-version.sh - git merge driver for the files that hold the version (VERSION, pom.xml,
# package.json), registered by configure_repo as 'qs-version' in .git/info/attributes.
#   merge-version.sh %O %A %B %P     base, ours (the result goes here), theirs, path
# Git calls it only when both sides changed the file. Every version tree writes its version
# into these files, so bringing develop into a tree after another release (git subir) always
# collides on the version line. The version that wins is the branch's own (ours), except on the
# mainline, which takes the version being released into it (theirs); every other change of the
# file (a new dependency in pom.xml) is merged as usual.
set -u
O="$1" A="$2" B="$3" P="${4:-}"
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_SUITE_DIR="${QUALITY_SUITE_DIR:-$SUITE}"
# shellcheck disable=SC1091
. "$SUITE/scripts/git-flow-lib.sh"
QS_POLICY_NO_DOCKER=1 qs_policy_load
win="$A"
[ "$(current_branch || true)" = "$QS_BR_MAINLINE" ] && win="$B"
# why: during a rebase "ours" is the new base and the branch's own commit is "theirs" (git publicar
# rebases '<v>/RELEASE' onto develop: the RELEASE version must win)
gd="$(git rev-parse --absolute-git-dir)"
{ [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && win="$B"
case "${P##*/}" in
pom.xml | package.json)
	ext="${P##*.}"
	tmp="$(git rev-parse --absolute-git-dir)/quality-suite/merge-version"
	rm -rf "$tmp"
	mkdir -p "$tmp"
	cp "$win" "$tmp/winner.$ext"
	cp "$O" "$tmp/base.$ext"
	cp "$A" "$tmp/ours.$ext"
	cp "$B" "$tmp/theirs.$ext"
	# shellcheck disable=SC1091
	. "$SUITE/scripts/qs-docker-lib.sh"
	if command -v docker >/dev/null 2>&1 &&
		qs_engine_tool "$tmp" version-align "winner.$ext" "base.$ext" "ours.$ext" "theirs.$ext" >/dev/null 2>&1; then
		git merge-file -L ours -L base -L theirs "$tmp/ours.$ext" "$tmp/base.$ext" "$tmp/theirs.$ext"
		rc=$?
		cat "$tmp/ours.$ext" >"$A"
	else
		git merge-file -L ours -L base -L theirs "$A" "$O" "$B"
		rc=$?
	fi
	rm -rf "$tmp"
	exit "$rc"
	;;
*)
	# VERSION: one line, the winning side
	[ "$win" = "$A" ] || cat "$B" >"$A"
	exit 0
	;;
esac
