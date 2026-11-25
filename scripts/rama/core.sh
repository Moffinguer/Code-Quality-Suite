#!/usr/bin/env bash
# rama/core.sh - shared helpers (origin, prompts, versions, engine, version commits) (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

# has_origin: tell whether the repository has a remote named origin.
# Arguments: none. Returns: 0 when it has one, 1 otherwise. Errors: none; prints nothing.
has_origin() { git remote get-url origin >/dev/null 2>&1; }
# fetch_origin: fetch and prune origin quietly when it exists.
# Arguments: none. Returns: 0. Errors: none; a failed fetch is ignored.
fetch_origin() { has_origin && git fetch -q --prune origin 2>/dev/null || true; }
# confirm QUESTION: ask a yes or no question on the terminal, the default being no.
# Arguments: $1 the question. Returns: 0 for y, Y, s, S, yes or si, or always when YES=1; 1 otherwise.
# Errors: none; an unreadable terminal counts as no.
confirm() {
	[ "$YES" = 1 ] && return 0
	local r
	printf '%s [y/N] ' "$1" >/dev/tty
	read -r r </dev/tty || r=""
	case "$r" in y | Y | s | S | yes | si) return 0 ;; esac
	return 1
}
# exists_ref REF: tell whether REF names an existing object (wrapper over qs_ref_exists, see qs-common.sh).
# Arguments: $1 a ref or revision. Return value: 0 when it resolves, 1 otherwise. Never prints.
exists_ref() { qs_ref_exists "$1"; }
# git_idx <index file> <git arguments>...: run git on a temporary index instead of the real one.
# Arguments: $1 the index file; $2... the git command. Exit status: the one of git.
git_idx() {
	local idx="$1"
	shift
	GIT_INDEX_FILE="$idx" git "$@"
}
# any local or remote branch named exactly <b>, or under the folder <b>/
taken() {
	exists_ref "refs/heads/$1" || exists_ref "refs/remotes/origin/$1" ||
		[ -n "$(git for-each-ref --count=1 "refs/heads/$1/" "refs/remotes/origin/$1/")" ]
}

# --- versions: Semantic Versioning (https://semver.org) ----------------------------------------
SEMVER_RELEASE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
# released or planned versions, lowest first: tags (a 'v' prefix is fine), version trees (also the
# ones set aside), the VERSION file of the mainline
known_versions() {
	local m
	m="$(best_ref "$QS_BR_MAINLINE" || true)"
	{
		git tag -l | sed 's/^[vV]//'
		all_branches | awk -F/ -v a="$QS_BR_ARCHIVE" 'NF > 1 { print ($1 == a ? $2 : $1) }'
		if [ -n "$m" ] && [ -n "$QS_BR_VERSION_FILE" ]; then git show "$m:$QS_BR_VERSION_FILE" 2>/dev/null || true; fi
	} | tr -d '\r ' | { grep -E "$SEMVER_RELEASE" || true; } | sort -t. -k1,1n -k2,2n -k3,3n -u
}
next_version() { # major|minor|patch -> the version after the highest known one
	local last ma mi pa
	last="$(known_versions | tail -n1)"
	last="${last:-0.0.0}"
	IFS=. read -r ma mi pa <<<"$last"
	case "$1" in
	major) echo "$((ma + 1)).0.0" ;; minor) echo "$ma.$((mi + 1)).0" ;; patch) echo "$ma.$mi.$((pa + 1))" ;;
	esac
}
# version_subject VERSION: print the commit subject of a version bump.
# Arguments: $1 version. Returns: 0 and prints 'chore(version): VERSION', or 'chore: VERSION' when
# that is longer than QS_COMMIT_SUBJECT_MAX (default 50). Errors: none.
version_subject() {
	local s="chore(version): $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: $1"
	printf '%s' "$s"
}

# The engine of the suite image, for edits that need a parser (pom.xml, CHANGELOG.md).
engine() { # engine <folder> <qs.py command> [args...]
	# shellcheck disable=SC1091
	[ -n "${QS_DOCKER_LIB:-}" ] || {
		. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"
		QS_DOCKER_LIB=1
	}
	command -v docker >/dev/null 2>&1 || return 1
	qs_engine_tool "$@"
}

# version_commit <branch> <version>: one commit on <branch> (without checking it out) that writes
# the version to VERSION, the pom.xml files that share the root version and package.json
# (branches.pom_version decides: update, snapshot, check, off). Nothing when they already hold it.
version_commit() {
	local b="$1" v="$2" parent gd tmp changed f blob mode tree commit
	[ -n "$QS_BR_VERSION_FILE" ] || [ "$QS_BR_POM" != off ] || return 0
	parent="$(git rev-parse "refs/heads/$b")"
	gd="$(git rev-parse --absolute-git-dir)/quality-suite"
	tmp="$gd/version-tmp"
	rm -rf "$tmp" "$tmp.index"
	mkdir -p "$tmp"
	# why: only the files that hold the version, as committed on the branch (the work tree is untouched)
	git ls-tree -r -z --name-only "$parent" | { grep -zE '(^|/)(pom\.xml|package\.json)$' || true; } >"$gd/version.list"
	if [ -n "$QS_BR_VERSION_FILE" ] && git cat-file -e "$parent:$QS_BR_VERSION_FILE" 2>/dev/null; then
		printf '%s\0' "$QS_BR_VERSION_FILE" >>"$gd/version.list"
	fi
	if [ -s "$gd/version.list" ]; then xargs -0 git archive --format=tar "$parent" <"$gd/version.list" | tar -xi -C "$tmp"; fi
	if changed="$(engine "$tmp" version-set "$v" --pom "$QS_BR_POM" --version-file "$QS_BR_VERSION_FILE" 2>"$gd/version.err")"; then
		sed 's/^\[quality-suite\] /[rama] /' "$gd/version.err" >&2
	else
		echo "[rama] WARN: the suite image could not run (Docker): only $QS_BR_VERSION_FILE is written." >&2
		[ "$QS_BR_POM" = off ] || echo "       pom.xml: mvn versions:set -DnewVersion=$v -DgenerateBackupPoms=false" >&2
		changed=""
		if [ -n "$QS_BR_VERSION_FILE" ] && [ "$(cat "$tmp/$QS_BR_VERSION_FILE" 2>/dev/null)" != "$v" ]; then
			mkdir -p "$(dirname "$tmp/$QS_BR_VERSION_FILE")"
			printf '%s\n' "$v" >"$tmp/$QS_BR_VERSION_FILE"
			changed="$QS_BR_VERSION_FILE"
		fi
	fi
	changed="$(printf '%s\n' "$changed" | tr -d '\r' | grep -v '^$' || true)"
	if [ -n "$changed" ]; then
		git_idx "$tmp.index" read-tree "$parent"
		while IFS= read -r f; do
			blob="$(git hash-object -w --path="$f" "$tmp/$f")"
			mode="$(git ls-tree --full-tree "$parent" -- "$f" | awk '{print $1}')"
			git_idx "$tmp.index" update-index --add --cacheinfo "${mode:-100644},$blob,$f"
		done <<<"$changed"
		tree="$(git_idx "$tmp.index" write-tree)"
		commit="$(git commit-tree "$tree" -p "$parent" -m "$(version_subject "$v")")"
		git update-ref "refs/heads/$b" "$commit" "$parent"
		say "$b: version $v in $(printf '%s' "$changed" | tr '\n' ' ')"
	fi
	rm -rf "$tmp" "$tmp.index" "$gd/version.list" "$gd/version.err"
}
