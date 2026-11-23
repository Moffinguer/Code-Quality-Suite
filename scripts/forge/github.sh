#!/usr/bin/env bash
# github.sh - GitHub provider of the forge layer (contract in scripts/forge/forge-lib.sh).
# Sourced by forge_load; needs QS_FORGE_REPO (owner/repo). Only gh's own credential store is
# used. Every call is `gh api`; reads are plain GETs, writes name their method.

# Run gh. Arguments: gh arguments. Returns: gh's status. QS_GH_BIN overrides the program.
forge_gh() {
	"${QS_GH_BIN:-gh}" "$@"
}

# Tell whether gh is installed. Arguments: none. Returns: 0 or 1.
forge_have_cli() {
	command -v "${QS_GH_BIN:-gh}" >/dev/null 2>&1
}

# Tell whether gh holds credentials. Arguments: none. Returns: 0 logged in, 1 otherwise.
forge_logged_in() {
	forge_have_cli && forge_gh auth status >/dev/null 2>&1
}

# Read-only: does the branch require a pull request? (GET rules/branches/<branch>).
# Arguments: branch. Returns: 0 a pull_request rule applies, 1 none, 2 API or parse error.
forge_requires_pr() {
	local out
	out="$(forge_gh api "repos/$QS_FORGE_REPO/rules/branches/$1" 2>/dev/null)" || return 2
	printf '%s' "$out" | python3 -I -c '
import json, sys
try:
    rules = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
sys.exit(0 if any(r.get("type") == "pull_request" for r in rules) else 1)'
}

# Open a pull request, or reuse the open one with the same head and base.
# Arguments: head base title body-file. Output: "<number> <url>". Returns: 0, 1 on failure.
forge_pr_open() {
	local head="$1" base="$2" title="$3" body="$4" out found
	found="$(forge_gh api "repos/$QS_FORGE_REPO/pulls?state=open&head=${QS_FORGE_REPO%%/*}:$head&base=$base" 2>/dev/null |
		python3 -I -c '
import json, sys
try:
    prs = json.load(sys.stdin)
except ValueError:
    prs = []
if prs:
    print(prs[0]["number"], prs[0]["html_url"])')" || found=""
	if [ -n "$found" ]; then
		echo "$found"
		return 0
	fi
	out="$(forge_gh api -X POST "repos/$QS_FORGE_REPO/pulls" -f "title=$title" -f "head=$head" \
		-f "base=$base" -F "body=@$body" 2>/dev/null)" || return 1
	printf '%s' "$out" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["number"], d["html_url"])'
}

# Print the state of a pull request. Arguments: number. Output: "<open|merged|closed>
# <head-sha> <merge-sha or ->". Returns: 0, 1 when the PR cannot be read.
forge_pr_state() {
	forge_gh api "repos/$QS_FORGE_REPO/pulls/$1" 2>/dev/null | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
state = "merged" if d.get("merged") else d.get("state", "closed")
print(state, d["head"]["sha"], d.get("merge_commit_sha") or "-")' 2>/dev/null
}

# Summarise the required checks of a pull request. Arguments: number. Output: green | pending
# | red (red wins over pending; a required check with no run is pending; no required check
# means every check run counts, none at all is green). Returns: 0, 1 when it cannot be read.
forge_pr_checks() {
	local pr sha base dir rc
	pr="$(forge_gh api "repos/$QS_FORGE_REPO/pulls/$1" 2>/dev/null)" || return 1
	sha="$(printf '%s' "$pr" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["head"]["sha"])')" || return 1
	base="$(printf '%s' "$pr" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["base"]["ref"])')" || return 1
	dir="$(mktemp -d)" || return 1
	# why: a missing rules answer only means "no required checks", it must not block
	forge_gh api "repos/$QS_FORGE_REPO/rules/branches/$base" >"$dir/rules" 2>/dev/null || echo '[]' >"$dir/rules"
	if ! forge_gh api "repos/$QS_FORGE_REPO/commits/$sha/check-runs?per_page=100" >"$dir/runs" 2>/dev/null; then
		rm -rf "$dir"
		return 1
	fi
	rc=0
	python3 -I - "$dir/rules" "$dir/runs" <<'PY' || rc=$?
import json, sys
rules = json.load(open(sys.argv[1]))
runs = json.load(open(sys.argv[2])).get("check_runs", [])
need = []
for r in rules:
    if r.get("type") == "required_status_checks":
        need += [c["context"] for c in r["parameters"]["required_status_checks"]]
latest = {}
for run in runs:
    latest[run["name"]] = run
state = "green"
for n in need or sorted(latest):
    run = latest.get(n)
    if run is None or run.get("status") != "completed":
        state = "pending" if state != "red" else state
    elif run.get("conclusion") not in ("success", "neutral", "skipped"):
        state = "red"
print(state)
PY
	rm -rf "$dir"
	return "$rc"
}

# Squash-merge a pull request with the given commit subject and body.
# Arguments: number subject body-file. Output: the new commit sha. Returns: 0, 1 when refused.
forge_pr_merge_squash() {
	local out
	out="$(forge_gh api -X PUT "repos/$QS_FORGE_REPO/pulls/$1/merge" -f merge_method=squash \
		-f "commit_title=$2" -F "commit_message=@$3" 2>/dev/null)" || return 1
	printf '%s' "$out" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("merged"):
    sys.exit(1)
print(d["sha"])'
}
