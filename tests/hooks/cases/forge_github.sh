#!/usr/bin/env bash
# Case forge_github: the forge layer (scripts/forge/forge-lib.sh, github.sh) against a FAKE gh
# (tests/hooks/fake-gh-forge; never the real GitHub API, no token). Covers PP1 (provider
# detection), PP4 (PR open / state / checks / squash merge), PP5 (tracked token refusal).
# Standalone: bash tests/hooks/cases/forge_github.sh   (also run by tests/hooks/run.sh)
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
SUITE="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() {
	echo "FAIL: forge_github: $*" >&2
	exit 1
}
ok() { echo "ok   forge_github: $*"; }

export FAKE_GH="$T/gh"
mkdir -p "$FAKE_GH/resp" "$T/bin"
cp "$SUITE/tests/hooks/fake-gh-forge" "$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export GIT_CONFIG_GLOBAL="$T/gitconfig" HOME="$T/home"
: >"$GIT_CONFIG_GLOBAL"
mkdir -p "$HOME"
git init -q "$T/repo"
cd "$T/repo"
git config user.email t@example.com
git config user.name tester

# shellcheck source=scripts/forge/forge-lib.sh
. "$SUITE/scripts/forge/forge-lib.sh"

# set_origin URL: point origin at URL (no network is ever used).
set_origin() {
	git remote remove origin 2>/dev/null || true
	git remote add origin "$1"
}

# serve METHOD PATH JSON: store the fake's answer for METHOD PATH.
serve() {
	printf '%s' "$3" >"$FAKE_GH/resp/${1}_$(printf '%s' "$2" | tr '/?&=:' '_____')"
}

# --- PP1: detection, no network -------------------------------------------------------------
for u in git@github.com:o/r.git git@github.com:o/r https://github.com/o/r.git https://github.com/o/r \
	ssh://git@github.com/o/r.git ssh://git@github.com/o/r; do
	set_origin "$u"
	[ "$(forge_provider)" = github ] && [ "$(forge_repo)" = o/r ] || fail "PP1 $u"
done
ok "PP1 github urls: provider github, repo o/r"
for u in git@gitlab.com:o/r.git https://dev.azure.com/o/p/_git/r https://example.com/o/r.git /tmp/some/bare.git \
	https://github.com.evil.example/o/r; do
	set_origin "$u"
	out="$(forge_provider || true)"
	[ -z "$out" ] && [ -z "$(forge_repo || true)" ] || fail "PP1 other host $u gave '$out'"
done
ok "PP1 other hosts: nothing"
[ ! -s "$FAKE_GH/calls.log" ] 2>/dev/null && ok "PP1 no gh call" || fail "PP1 called gh"
git remote remove origin
[ -z "$(forge_provider || true)" ] && ok "PP1 no remote: nothing" || fail "PP1 no remote"

set_origin git@github.com:o/r.git
forge_load || fail "forge_load"
[ "$QS_FORGE_PROVIDER" = github ] && [ "$QS_FORGE_REPO" = o/r ] && ok "forge_load sets the provider and the repo" || fail "forge_load vars"

# --- PP4: pull request open ------------------------------------------------------------------
printf 'Body line 1\nBody line 2\n' >"$T/body.md"
serve GET 'repos/o/r/pulls?state=open&head=o:1.0.0/RELEASE&base=develop' '[]'
serve POST 'repos/o/r/pulls' '{"number": 7, "html_url": "https://github.com/o/r/pull/7"}'
out="$(forge_pr_open 1.0.0/RELEASE develop "chore(release): 1.0.0" "$T/body.md")"
[ "$out" = "7 https://github.com/o/r/pull/7" ] && ok "pr_open creates a PR and prints number and URL" || fail "pr_open: $out"
grep -q '^POST repos/o/r/pulls$' "$FAKE_GH/calls.log" && grep -q '^  head=1.0.0/RELEASE$' "$FAKE_GH/calls.log" &&
	grep -q '^  body=Body line 1|Body line 2|$' "$FAKE_GH/calls.log" && grep -q '^  title=chore(release): 1.0.0$' "$FAKE_GH/calls.log" &&
	ok "pr_open sends title, head, base and the body file" || fail "pr_open fields"
: >"$FAKE_GH/calls.log"
serve GET 'repos/o/r/pulls?state=open&head=o:1.0.0/RELEASE&base=develop' '[{"number": 9, "html_url": "https://github.com/o/r/pull/9"}]'
out="$(forge_pr_open 1.0.0/RELEASE develop t "$T/body.md")"
[ "$out" = "9 https://github.com/o/r/pull/9" ] && ! grep -q '^POST' "$FAKE_GH/calls.log" &&
	ok "pr_open reuses the open PR with the same head and base" || fail "pr_open reuse: $out"
touch "$FAKE_GH/apierror"
forge_pr_open x develop t "$T/body.md" >/dev/null 2>&1 && fail "pr_open on API error succeeded"
rm "$FAKE_GH/apierror"
ok "pr_open fails on an API error"

# --- PP4: state -------------------------------------------------------------------------------
serve GET 'repos/o/r/pulls/7' '{"state": "open", "merged": false, "head": {"sha": "aaa"}, "base": {"ref": "develop"}, "merge_commit_sha": null}'
[ "$(forge_pr_state 7)" = "open aaa -" ] && ok "pr_state open" || fail "pr_state open"
serve GET 'repos/o/r/pulls/7' '{"state": "closed", "merged": true, "head": {"sha": "aaa"}, "base": {"ref": "develop"}, "merge_commit_sha": "bbb"}'
[ "$(forge_pr_state 7)" = "merged aaa bbb" ] && ok "pr_state merged with merge sha" || fail "pr_state merged"
serve GET 'repos/o/r/pulls/7' '{"state": "closed", "merged": false, "head": {"sha": "aaa"}, "base": {"ref": "develop"}, "merge_commit_sha": null}'
[ "$(forge_pr_state 7)" = "closed aaa -" ] && ok "pr_state closed" || fail "pr_state closed"
forge_pr_state 404 >/dev/null 2>&1 && fail "pr_state of an unknown PR succeeded"
ok "pr_state fails for an unknown PR"

# --- PP4: checks ------------------------------------------------------------------------------
serve GET 'repos/o/r/pulls/7' '{"state": "open", "merged": false, "head": {"sha": "aaa"}, "base": {"ref": "develop"}, "merge_commit_sha": null}'
serve GET 'repos/o/r/rules/branches/develop' '[{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "ci / flow"}, {"context": "ci / quality"}]}}]'
runs() { serve GET 'repos/o/r/commits/aaa/check-runs?per_page=100' "$1"; }
runs '{"check_runs": [{"name": "ci / flow", "status": "completed", "conclusion": "success"}, {"name": "ci / quality", "status": "completed", "conclusion": "success"}, {"name": "other", "status": "completed", "conclusion": "failure"}]}'
[ "$(forge_pr_checks 7)" = green ] && ok "pr_checks green (a non-required failure is ignored)" || fail "checks green"
runs '{"check_runs": [{"name": "ci / flow", "status": "completed", "conclusion": "success"}, {"name": "ci / quality", "status": "in_progress", "conclusion": null}]}'
[ "$(forge_pr_checks 7)" = pending ] && ok "pr_checks pending (required check still running)" || fail "checks pending"
runs '{"check_runs": [{"name": "ci / flow", "status": "completed", "conclusion": "success"}]}'
[ "$(forge_pr_checks 7)" = pending ] && ok "pr_checks pending (required check has no run)" || fail "checks missing run"
runs '{"check_runs": [{"name": "ci / flow", "status": "completed", "conclusion": "failure"}, {"name": "ci / quality", "status": "queued", "conclusion": null}]}'
[ "$(forge_pr_checks 7)" = red ] && ok "pr_checks red wins over pending" || fail "checks red"
runs '{"check_runs": [{"name": "ci / flow", "status": "completed", "conclusion": "skipped"}, {"name": "ci / quality", "status": "completed", "conclusion": "neutral"}]}'
[ "$(forge_pr_checks 7)" = green ] && ok "pr_checks skipped and neutral count as green" || fail "checks skipped"
serve GET 'repos/o/r/rules/branches/develop' '[]'
runs '{"check_runs": [{"name": "a", "status": "completed", "conclusion": "success"}, {"name": "b", "status": "completed", "conclusion": "failure"}]}'
[ "$(forge_pr_checks 7)" = red ] && ok "pr_checks without required checks looks at every run" || fail "checks no required"
runs '{"check_runs": []}'
[ "$(forge_pr_checks 7)" = green ] && ok "pr_checks with no runs at all is green" || fail "checks empty"
rm "$FAKE_GH/resp/GET_repos_o_r_commits_aaa_check-runs_per_page_100"
forge_pr_checks 7 >/dev/null 2>&1 && fail "pr_checks without a readable run list succeeded"
ok "pr_checks fails when the runs cannot be read"

# --- PP4: squash merge ------------------------------------------------------------------------
: >"$FAKE_GH/calls.log"
serve PUT 'repos/o/r/pulls/7/merge' '{"merged": true, "sha": "ccc"}'
out="$(forge_pr_merge_squash 7 "chore(release): 1.0.0" "$T/body.md")"
[ "$out" = ccc ] && grep -q '^PUT repos/o/r/pulls/7/merge$' "$FAKE_GH/calls.log" && grep -q '^  merge_method=squash$' "$FAKE_GH/calls.log" &&
	grep -q '^  commit_title=chore(release): 1.0.0$' "$FAKE_GH/calls.log" && grep -q '^  commit_message=Body line 1|Body line 2|$' "$FAKE_GH/calls.log" &&
	ok "pr_merge_squash sends squash, subject and body, prints the sha" || fail "merge: $out"
serve PUT 'repos/o/r/pulls/7/merge' '{"merged": false, "message": "not mergeable"}'
forge_pr_merge_squash 7 s "$T/body.md" >/dev/null 2>&1 && fail "merge reported success for merged=false"
ok "pr_merge_squash fails when GitHub does not merge"

# --- login ------------------------------------------------------------------------------------
forge_have_cli && forge_logged_in && ok "logged in with the fake gh" || fail "logged in"
touch "$FAKE_GH/loggedout"
forge_logged_in && fail "logged in although the fake is logged out"
ok "not logged in is detected"
rm "$FAKE_GH/loggedout"
QS_GH_BIN=no-such-gh-program
export QS_GH_BIN
forge_have_cli && fail "gh found although QS_GH_BIN is missing"
ok "missing gh is detected"
unset QS_GH_BIN

# --- PP5: tracked token -----------------------------------------------------------------------
TOK="dummy-$$-$RANDOM"
printf 'value=%s\n' "$TOK" >leak.txt
git add leak.txt
git commit -q -m "chore: leak"
out="$(GH_TOKEN=$TOK forge_check_token 2>&1 || true)"
GH_TOKEN=$TOK forge_check_token 2>/dev/null && fail "tracked GH_TOKEN accepted"
case "$out" in *"$TOK"*) fail "the refusal prints the token" ;; esac
ok "PP5 a token found in a tracked file is refused and never printed"
GITHUB_TOKEN=$TOK forge_check_token 2>/dev/null && fail "tracked GITHUB_TOKEN accepted"
GH_TOKEN=other-$TOK forge_check_token 2>/dev/null && ok "PP5 a token not in any tracked file passes" || fail "other token refused"
forge_check_token && ok "PP5 no token passes" || fail "no token refused"
