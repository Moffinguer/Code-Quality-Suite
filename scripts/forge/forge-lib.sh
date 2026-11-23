#!/usr/bin/env bash
# forge-lib.sh - forge provider layer: detect the forge behind a remote, load its provider file.
# Sourced by scripts/forge/delivery.sh and by the publish commands; never run directly.
#
# Interface (stable; 7.2.0 adds its issue/project functions as NEW files of this directory,
# for example scripts/forge/github-issues.sh, and never edits these names):
#
# Generic (this file; no network call):
#   forge_provider [<remote>]    print the provider id (only "github") for the remote's URL,
#                                nothing for any other host. Default remote: origin.
#   forge_repo [<remote>]        print "owner/repo" of a GitHub remote, nothing otherwise.
#   forge_load [<remote>]        set QS_FORGE_PROVIDER and QS_FORGE_REPO, then source the
#                                provider file (<id>.sh); return 1 when there is no provider.
#   forge_check_token            return 1 (naming the fix, never the value) when GH_TOKEN or
#                                GITHUB_TOKEN holds a value that appears in a tracked file.
#
# Provider contract (defined by <id>.sh; all use QS_FORGE_REPO; return 0 ok, 1 failed):
#   forge_have_cli               the provider's CLI is installed.
#   forge_logged_in              the CLI holds credentials (its own store only).
#   forge_requires_pr <branch>   read-only: 0 the branch requires a pull request, 1 it does
#                                not, 2 the answer could not be read (API error).
#   forge_pr_open <head> <base> <title> <body-file>
#                                print "<number> <url>"; reuses an open PR with that head
#                                and base.
#   forge_pr_state <n>           print "<open|merged|closed> <head-sha> <merge-sha|->".
#   forge_pr_checks <n>          print green | pending | red over the required checks of the
#                                base branch (all check runs when none is required).
#   forge_pr_merge_squash <n> <subject> <body-file>
#                                squash-merge the PR with that subject and body; print the
#                                new commit sha.
#
# Environment: QS_FORGE_DIR (this directory), QS_GH_BIN (name or path of gh; default gh),
# QS_TAG (message prefix; default forge). Messages go to stderr and never contain an
# environment value.

_QS_FORGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS_FORGE_DIR="${QS_FORGE_DIR:-$_QS_FORGE_LIB_DIR}"

# Print a tagged message on stderr. Arguments: message words. Returns: 0.
forge_say() {
	echo "[${QS_TAG:-forge}] $*" >&2
}

# Print the remote's URL. Arguments: [remote] (default origin). Output: the URL on stdout.
# Returns: 0, or 1 when the remote does not exist.
forge_url() {
	git remote get-url "${1:-origin}" 2>/dev/null
}

# Print owner/repo when the URL is a GitHub one (https, ssh or scp form), else nothing.
# Arguments: url. Output: owner/repo on stdout. Returns: 0 for GitHub, 1 for any other host.
forge_github_slug() {
	local u="$1"
	case "$u" in
	https://github.com/* | http://github.com/*) u="${u#*://github.com/}" ;;
	git@github.com:*) u="${u#git@github.com:}" ;;
	ssh://git@github.com/*) u="${u#ssh://git@github.com/}" ;;
	*) return 1 ;;
	esac
	u="${u%/}"
	u="${u%.git}"
	[[ $u =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
	printf '%s\n' "$u"
}

# Print the provider id of a remote. Arguments: [remote] (default origin). Output: "github" or
# nothing. Returns: 0 when a provider was found, 1 otherwise. No network call.
forge_provider() {
	local url
	url="$(forge_url "${1:-origin}")" || return 1
	if forge_github_slug "$url" >/dev/null; then
		echo github
		return 0
	fi
	return 1
}

# Print owner/repo of a remote. Arguments: [remote] (default origin). Output: owner/repo, or
# nothing when the host is not a known forge. Returns: 0 or 1.
forge_repo() {
	local url
	url="$(forge_url "${1:-origin}")" || return 1
	forge_github_slug "$url"
}

# Detect the provider of a remote and source its file. Arguments: [remote] (default origin).
# Sets QS_FORGE_PROVIDER and QS_FORGE_REPO. Returns: 0 when loaded, 1 when there is no
# provider or its file is missing.
forge_load() {
	local remote="${1:-origin}" id
	id="$(forge_provider "$remote")" || return 1
	[ -f "$QS_FORGE_DIR/$id.sh" ] || return 1
	export QS_FORGE_PROVIDER="$id"
	QS_FORGE_REPO="$(forge_repo "$remote")" || return 1
	export QS_FORGE_REPO
	# why: the provider file is chosen at run time
	# shellcheck source=/dev/null
	. "$QS_FORGE_DIR/$id.sh"
}

# Refuse when GH_TOKEN / GITHUB_TOKEN holds a value found in a tracked file (credentials come
# only from the CLI's own store). Arguments: none. Returns: 0 when fine, 1 when refused (the
# message names the fix and never prints the value).
forge_check_token() {
	local tok
	for tok in "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}"; do
		[ -n "$tok" ] || continue
		if git grep -qF -f <(printf '%s\n' "$tok") 2>/dev/null; then
			forge_say "refusing: GH_TOKEN/GITHUB_TOKEN comes from a tracked file. Unset it and use 'gh auth login'."
			return 1
		fi
	done
	return 0
}
