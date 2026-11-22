#!/usr/bin/env bash
# git-migracion.sh (git alias: git migracion) - the MIGRATION special branch of a version.
# qs-alias: migracion
#   git migracion [<version>]
#       creates '<version>/MIGRATION' at '<version>/ORIGINAL' and checks it out. The version is the
#       one of the current branch ('<v>/ORIGINAL') when not given. Refused when MIGRATION is
#       disabled or the flow is not squash, when '<v>/MIGRATION' is already open, and once any
#       other branch of the version exists (MIGRATION is first: while it is open nothing else of
#       the version can be created). 'git np <version> --migracion' does the same on creation.
# Children: 'git convertir-padre' on MIGRATION gives '<v>/MIGRATION/ORIGINAL'. 'git integra' squashes
# it into '<v>/ORIGINAL' as one 'build: <subject>' commit (see integra_squash in git-rama.sh).
# This file is also sourced by git-rama.sh for mg_create and mg_after_squash.

# shellcheck disable=SC1091
if ! declare -F special_enabled >/dev/null 2>&1; then
	. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-flow-lib.sh"
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

# Print an error and exit.
# Arguments: $@ message. Returns: never (exit 1).
mg_die() {
	echo "[migracion] $*" >&2
	exit 1
}

# Print a progress line.
# Arguments: $@ message. Returns: 0.
mg_say() { echo "[migracion] $*"; }

# Whether a branch exists locally or on origin.
# Arguments: $1 branch. Returns: 0 when it does, 1 otherwise.
mg_exists() {
	git rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1 ||
		git rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null 2>&1
}

# Publish new branches through qs_publish_new when the suite has it (autopublish); a guarded stub:
# without it the branches stay local.
# Arguments: $@ branches. Returns: 0 (a failed push keeps the local branch).
mg_publish() {
	if declare -F qs_publish_new >/dev/null 2>&1; then qs_publish_new "$@" || true; fi
	return 0
}

# The branches of a version other than its ORIGINAL (local and origin, one per line).
# Arguments: $1 version. Returns: 0; prints nothing when there are none.
mg_others() {
	local v="$1"
	{
		git for-each-ref --format='%(refname:short)' "refs/heads/$v/"
		git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/$v/"
	} 2>/dev/null | { grep -vxF -e "$v/$QS_BR_LEAF" || true; } | LC_ALL=C sort -u
}

# Create '<v>/MIGRATION' at '<v>/ORIGINAL', publish it and check it out.
# Arguments: $1 version. Returns: 0; exits through mg_die when MIGRATION is disabled, the version
# has no ORIGINAL, MIGRATION is already open or another branch of the version exists.
mg_create() {
	local v="$1" m="$1/MIGRATION" base others open
	special_enabled MIGRATION ||
		mg_die "MIGRATION is not enabled (it needs branches.flow: squash and branches.special.MIGRATION)"
	mg_exists "$v/$QS_BR_LEAF" || mg_die "'$v/$QS_BR_LEAF' does not exist: git np $v"
	if open="$(special_migration_open "$v")"; then
		mg_die "$v already has an open MIGRATION ($open)"
	fi
	others="$(mg_others "$v")"
	if [ -n "$others" ]; then
		mg_die "$v already has other branches ($(printf '%s' "$others" | head -n3 | tr '\n' ' ')...): MIGRATION must be the first, nothing else may exist"
	fi
	base="$(best_ref "$v/$QS_BR_LEAF")"
	git branch -q --no-track "$m" "$base"
	mg_publish "$m"
	git checkout -q "$m"
	mg_say "created '$m' from '$base': nothing else of $v can be created until it is integrated"
	mg_say "children: git convertir-padre, then git nr <name>; finish with git integra"
}

# Whether DOCS mode is on: DOCS enabled and required at the release.
# Arguments: none. Returns: 0 when on, 1 otherwise.
mg_docs_mode() {
	special_enabled DOCS && [ "$(special_prop DOCS ON_RELEASE)" = required ]
}

# After the MIGRATION squash of a version: delete what is left under '<v>/MIGRATION/' that is
# already integrated (local and origin), then, when the lock is gone and the repository is in DOCS
# mode, create '<v>/DOCS' at '<v>/ORIGINAL' (unless it exists) and publish it. Integrated leftovers
# are the children kept at their own integration; the ones named as pending (a --force squash
# left them out) are kept, and so is everything when the MIGRATION branch itself was kept.
# The origin deletes are one '--atomic' push, each leased to the sha of its 'origin/<ref>' seen
# here (--force-with-lease=<ref>:<sha>): when a lease is lost (origin moved since), the push is
# refused, a warning names the branch and its local copy is kept. A local copy goes only after its
# origin delete succeeded (or when it is local only).
# Arguments: $1 version, $2... branches that were pending at the squash. Returns: 0.
mg_after_squash() {
	local v="$1" b pend=" ${*:2} "
	local -a gone=() leases=() refs=()
	if git rev-parse -q --verify "refs/heads/$v/MIGRATION" >/dev/null 2>&1 ||
		git rev-parse -q --verify "refs/heads/$v/MIGRATION/$QS_BR_LEAF" >/dev/null 2>&1; then
		mg_say "the MIGRATION branch was kept: its lock stays until it is deleted"
		return 0
	fi
	while IFS= read -r b; do
		case "$b" in "$v"/MIGRATION | "$v"/MIGRATION/*) ;; *) continue ;; esac
		case "$pend" in *" $b "*)
			echo "[migracion] '$b' was not integrated: kept (the MIGRATION lock stays until it goes)" >&2
			continue
			;;
		esac
		if git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null 2>&1; then
			gone+=("$b")
			leases+=("--force-with-lease=refs/heads/$b:$(git rev-parse "refs/remotes/origin/$b")")
			refs+=(":refs/heads/$b")
		else
			git branch -q -D "$b" 2>/dev/null || true
			mg_say "deleted '$b' locally"
		fi
	done < <(mg_others "$v")
	if [ "${#refs[@]}" -gt 0 ]; then
		if git push -q --atomic "${leases[@]}" origin "${refs[@]}" 2>/dev/null; then
			for b in "${gone[@]}"; do
				git branch -q -D "$b" 2>/dev/null || true
				mg_say "deleted '$b' locally and on origin"
			done
		else
			for b in "${gone[@]}"; do
				echo "[migracion] warning: '$b' not deleted on origin (the atomic push was refused: a lease was lost): local copy kept" >&2
			done
		fi
	fi
	special_migration_open "$v" >/dev/null && return 0
	if mg_docs_mode && ! mg_exists "$v/DOCS"; then
		git branch -q --no-track "$v/DOCS" "$(best_ref "$v/$QS_BR_LEAF")"
		mg_publish "$v/DOCS"
		mg_say "created '$v/DOCS' next to '$v/$QS_BR_LEAF' (MIGRATION is in: the lock is gone)"
	fi
	return 0
}

# Entry point of the git alias.
# Arguments: the command line after 'git migracion': an optional version. Returns: 0; exits
# through mg_die on a refusal or a bad argument.
mg_main() {
	local v="${1:-}" cur
	[ "$#" -le 1 ] || mg_die "usage: git migracion [<version>]"
	case "$v" in -*) mg_die "usage: git migracion [<version>]" ;; esac
	qs_policy_load
	git fetch -q --prune origin 2>/dev/null || true
	if [ -z "$v" ]; then
		cur="$(current_branch)" || mg_die "detached HEAD: git migracion <version>"
		is_parent_branch "$cur" && [ "$(branch_node "$cur")" = "${cur%%/*}" ] ||
			mg_die "run it on '<version>/$QS_BR_LEAF' (or give the version): you are on '$cur'"
		v="${cur%%/*}"
	fi
	valid_branch_name "$v/$QS_BR_LEAF" >/dev/null 2>&1 || mg_die "'$v' is not a version of the model"
	mg_create "$v"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then mg_main "$@"; fi
