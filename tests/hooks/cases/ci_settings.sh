#!/usr/bin/env bash
# Case ci_settings: scripts/gh-settings.sh against a FAKE gh (never the real GitHub API).
# The fake serves stored JSON responses from $FAKE_GH/resp and records every call in
# $FAKE_GH/calls.log (write calls also log their body in $FAKE_GH/bodies.log).
# Standalone: bash tests/hooks/cases/ci_settings.sh   (also run by tests/hooks/run.sh)
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
SUITE="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() {
	echo "FAIL: ci_settings: $*" >&2
	exit 1
}
ok() { echo "ok   ci_settings: $*"; }

export FAKE_GH="$T/gh"
mkdir -p "$FAKE_GH/resp" "$T/bin"
cp "$SUITE/tests/hooks/fake-gh.sh" "$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

REAL="$SUITE/.github/repo-settings.json"
mkdir -p "$T/cfg"
cp "$REAL" "$T/cfg/repo-settings.json"
CFG="$T/cfg/repo-settings.json"

# Write the live state that matches the JSON exactly ($1: python snippet editing d/live first).
mk_state() {
	rm -f "$FAKE_GH"/resp/*
	python3 -I - "$CFG" "$FAKE_GH/resp" "${1:-pass}" <<'PY'
import json, sys
cfg, out, tweak = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(cfg))
def w(name, obj):
    json.dump(obj, open(out + "/repos_o_r" + name, "w"))
repo = dict(d["repository"])
repo["security_and_analysis"] = {k: {"status": "enabled" if v else "disabled"}
    for k, v in d["security"].items() if k != "dependabot_alerts"}
if "drift" in tweak:
    repo["has_wiki"] = True
a = d["actions"]
w("", repo)
if d["security"]["dependabot_alerts"] and "noalerts" not in tweak:
    open(out + "/repos_o_r_vulnerability-alerts", "w").write("")
w("_actions_permissions", {"enabled": True, "allowed_actions": a["allowed_actions"]})
w("_actions_permissions_selected-actions", {k: a[k] for k in ("github_owned_allowed", "verified_allowed", "patterns_allowed")})
w("_actions_permissions_workflow", {"default_workflow_permissions": "write" if "drift" in tweak else a["default_workflow_permissions"], "can_approve_pull_request_reviews": a["can_approve_pull_request_reviews"]})
w("_actions_permissions_fork-pr-contributor-approval", {"approval_policy": a["fork_pr_approval"]})
lst = []
for i, r in enumerate(d["rulesets"], 1):
    if "drift" in tweak and r["name"] == "release-tags":
        continue
    rs = dict(r)
    if "drift" in tweak and r["name"] == "original":
        rs["rules"] = []
    lst.append({"id": i, "name": r["name"]})
    api_rules = [{"type": t} for t in rs["rules"]]
    if "mainpr" in tweak and r["name"] == "mainline":
        api_rules += [{"type": "pull_request", "parameters": {"required_approving_review_count": 0}},
            {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": c} for c in d["required_checks"]]}}]
    w("_rulesets_%d" % i, {"id": i, "name": r["name"], "target": r["target"], "enforcement": r["enforcement"],
        "conditions": {"ref_name": {"include": r["include"], "exclude": r["exclude"]}},
        "rules": api_rules, "bypass_actors": r["bypass_actors"]})
if "drift" in tweak:
    lst.append({"id": 98, "name": "ot-tags"})
    w("_rulesets_98", {"id": 98, "name": "ot-tags", "target": "tag", "enforcement": "active",
        "conditions": {"ref_name": {"include": ["refs/tags/ot/**"], "exclude": []}}, "rules": [{"type": "update"}], "bypass_actors": []})
if "extra" in tweak:
    lst.append({"id": 99, "name": "stray"})
    w("_rulesets_99", {"id": 99, "name": "stray", "target": "branch", "enforcement": "active",
        "conditions": {"ref_name": {"include": ["refs/heads/x"], "exclude": []}}, "rules": [], "bypass_actors": []})
w("_rulesets", lst)
PY
}
reset_calls() { rm -f "$FAKE_GH/calls.log" "$FAKE_GH/bodies.log"; }
writes() { { grep -vc '^GET ' "$FAKE_GH/calls.log" 2>/dev/null || true; } | head -1; }
GS="bash $SUITE/scripts/gh-settings.sh --repo o/r --config $CFG"

# RS1: --diff is the default, reports differences and never writes
mk_state drift
reset_calls
out="$($GS 2>&1)" || fail "diff failed: $out"
echo "$out" | grep -q 'repository.has_wiki: true -> false' && echo "$out" | grep -q 'ruleset ot-tags' &&
	echo "$out" | grep -q 'ruleset original.rules' && echo "$out" | grep -q 'default_workflow_permissions' &&
	ok "diff lists drift" || fail "diff output: $out"
[ "$(writes)" = 0 ] && ok "diff sends no write call" || fail "diff wrote"
mk_state pass
out="$($GS --diff 2>&1)"
echo "$out" | grep -q 'no differences' && ok "no differences when equal" || fail "equal state: $out"

# RS2: apply sends only the differing settings; second run sends nothing
mk_state drift
reset_calls
$GS --apply >"$T/apply.out" 2>&1 || fail "apply failed: $(cat "$T/apply.out")"
grep -q '^PATCH repos/o/r$' "$FAKE_GH/calls.log" && grep -q '^POST repos/o/r/rulesets$' "$FAKE_GH/calls.log" &&
	grep -q '^PUT repos/o/r/rulesets/2$' "$FAKE_GH/calls.log" && grep -q '^PUT repos/o/r/actions/permissions/workflow$' "$FAKE_GH/calls.log" &&
	ok "apply sends the differing calls" || fail "apply calls: $(cat "$FAKE_GH/calls.log")"
[ "$(writes)" = 4 ] && ok "apply sends only 4 writes" || fail "write count $(writes)"
grep -q '^PATCH repos/o/r {"has_wiki": false}$' "$FAKE_GH/bodies.log" && ok "PATCH body has only the differing key" ||
	fail "patch body: $(cat "$FAKE_GH/bodies.log")"
mk_state pass
reset_calls
$GS --apply >"$T/apply2.out" 2>&1
grep -q 'no differences' "$T/apply2.out" && [ "$(writes)" = 0 ] && ok "second apply sends nothing" || fail "second apply"
mk_state noalerts
reset_calls
$GS --apply >/dev/null 2>&1
grep -q '^PUT repos/o/r/vulnerability-alerts$' "$FAKE_GH/calls.log" && ok "dependabot alerts enabled" || fail "alerts"
mk_state extra
reset_calls
$GS --apply >/dev/null 2>&1
[ "$(writes)" = 0 ] && ok "unknown ruleset is never deleted without --prune" || fail "deleted without prune"
$GS --apply --prune >/dev/null 2>&1
grep -q '^DELETE repos/o/r/rulesets/99$' "$FAKE_GH/calls.log" && ok "--prune deletes the stray ruleset" || fail "prune"

touch "$FAKE_GH/loggedout"
out="$($GS 2>&1)" && fail "logged-out gh was accepted"
echo "$out" | grep -q 'gh auth login' && ok "refuses when not logged in" || fail "logout message: $out"
rm "$FAKE_GH/loggedout"
git init -q -b main "$T/w"
printf 'token=ghp_fakeSecretValue123\n' >"$T/w/.env"
(cd "$T/w" && git add .env && git -c user.email=t@e -c user.name=t commit -q -m "feat: env")
out="$(cd "$T/w" && GH_TOKEN=ghp_fakeSecretValue123 bash "$SUITE/scripts/gh-settings.sh" --repo o/r 2>&1)" && fail "tracked token accepted"
echo "$out" | grep -q 'tracked file' && ok "refuses a token that comes from a tracked file" || fail "token message: $out"
(cd "$T/w" && GH_TOKEN=other bash "$SUITE/scripts/gh-settings.sh" --repo o/r >/dev/null 2>&1) &&
	ok "an unrelated token is fine" || fail "token wrongly refused"
git -C "$T/w" remote add origin https://example.com/o/r.git
out="$(cd "$T/w" && bash "$SUITE/scripts/gh-settings.sh" 2>&1)" && fail "non-GitHub origin accepted"
echo "$out" | grep -q 'not a GitHub URL' && ok "refuses a non-GitHub origin" || fail "origin message: $out"
git -C "$T/w" remote set-url origin git@github.com:o/r.git
(cd "$T/w" && bash "$SUITE/scripts/gh-settings.sh" >/dev/null 2>&1) && ok "ssh GitHub origin parsed" || fail "ssh origin"

# RS4: the JSON has every row of the spec and unknown keys are refused
python3 -I - "$REAL" <<'PY' && ok "JSON holds every desired-state and ruleset row" || fail "JSON content"
import json, sys
d = json.load(open(sys.argv[1]))
r, s, a = d["repository"], d["security"], d["actions"]
assert r["default_branch"] == "main" and r["allow_squash_merge"] is True
assert r["allow_merge_commit"] is False and r["allow_rebase_merge"] is False
assert r["delete_branch_on_merge"] is True and r["allow_auto_merge"] is False
assert r["allow_update_branch"] is False and r["has_wiki"] is False and r["has_discussions"] is False
assert r["has_issues"] is True and r["has_projects"] is True
assert r["squash_merge_commit_title"] == "COMMIT_OR_PR_TITLE" and r["squash_merge_commit_message"] == "COMMIT_MESSAGES"
assert d["required_checks"] == ["ci / plan", "ci / flow", "ci / quality", "ci / selftest"]
assert all(s.values()) and set(s) == {"secret_scanning", "secret_scanning_push_protection", "dependabot_alerts"}
assert a["allowed_actions"] == "selected" and a["default_workflow_permissions"] == "read"
assert a["can_approve_pull_request_reviews"] is False and a["fork_pr_approval"] == "all_external_contributors"
rs = {x["name"]: x for x in d["rulesets"]}
assert set(rs) == {"mainline", "original", "checkpoint", "release-tags"}
assert rs["mainline"]["rules"] == ["deletion", "non_fast_forward"]
assert rs["original"]["rules"] == ["non_fast_forward"] and "release" not in rs
assert rs["checkpoint"]["rules"] == ["creation"] and rs["checkpoint"]["include"] == ["refs/heads/**/CHECKPOINT-*"]
assert rs["release-tags"]["target"] == "tag" and "ot-tags" not in rs
assert all(x["bypass_actors"] == [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}] for x in rs.values())
PY
python3 -I - "$REAL" "$T/bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repository"]["surprise"] = True
json.dump(d, open(sys.argv[2], "w"))
PY
out="$($GS --config "$T/bad.json" 2>&1)" && fail "unknown key accepted"
echo "$out" | grep -q 'unknown key repository.surprise' && ok "unknown keys refused" || fail "unknown key message: $out"
grep -q 'qs-alias:' "$SUITE/scripts/git-flow-lib.sh" && grep -q '^# qs-alias: configurar-github$' "$SUITE/scripts/gh-settings.sh" &&
	ok "alias declared" || fail "alias"
# RS8: the mainline pull request rules follow branches.delivery (quality-rules.json beside the JSON)
set_delivery() { printf '{"branches": {"delivery": "%s"}}\n' "$1" >"$T/cfg/quality-rules.json"; }
set_delivery pr
mk_state pass
reset_calls
out="$($GS 2>&1)"
echo "$out" | grep -q 'ruleset mainline.rules' && echo "$out" | grep -q 'ruleset mainline.required_checks' &&
	ok "pr: both rules are added" || fail "pr diff: $out"
$GS --apply >/dev/null 2>&1
grep -q '"type": "pull_request".*"required_approving_review_count": 0' "$FAKE_GH/bodies.log" &&
	grep -q '"context": "ci / flow"' "$FAKE_GH/bodies.log" && ok "pr: body holds 0 approvals and the four checks" ||
	fail "pr body: $(cat "$FAKE_GH/bodies.log")"
mk_state mainpr
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && ok "pr: served state is equal" || fail "pr equal: $out"
set_delivery push
out="$($GS 2>&1)"
echo "$out" | grep -q 'ruleset mainline.rules' && echo "$out" | grep -q 'pull_request' &&
	ok "push: both rules shown as removals" || fail "push diff: $out"
reset_calls
$GS --apply >/dev/null 2>&1
grep -q '^PUT repos/o/r/rulesets/1$' "$FAKE_GH/calls.log" && ! grep -q 'pull_request' "$FAKE_GH/bodies.log" &&
	ok "push: the PUT drops the rules" || fail "push body: $(cat "$FAKE_GH/bodies.log")"
mk_state pass
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && ok "push: plain mainline is equal" || fail "push equal: $out"
set_delivery auto
mk_state mainpr
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && echo "$out" | grep -q 'delivery auto: mainline pull request rules left as served' &&
	ok "auto: served rules are kept and reported" || fail "auto: $out"
mk_state pass
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && ok "auto: no rules served, none added" || fail "auto plain: $out"
rm "$T/cfg/quality-rules.json"
mk_state mainpr
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && ok "missing rules file = auto" || fail "missing file: $out"
printf '{"branches": {}}\n' >"$T/cfg/quality-rules.json"
out="$($GS 2>&1)"
echo "$out" | grep -q 'no differences' && ok "missing key = auto" || fail "missing key: $out"
set_delivery weird
out="$($GS 2>&1)" && fail "bad delivery accepted"
echo "$out" | grep -q 'branches.delivery must be' && ok "bad delivery refused" || fail "bad delivery: $out"
rm "$T/cfg/quality-rules.json"

# RS9: the fake gh is the shared helper
[ -x "$SUITE/tests/hooks/fake-gh.sh" ] && grep -q 'tests/hooks/fake-gh.sh' "$SUITE/tests/hooks/cases/ci_settings.sh" &&
	ok "fake gh lives in tests/hooks/fake-gh.sh" || fail "fake gh helper"
echo "ci_settings passed"
