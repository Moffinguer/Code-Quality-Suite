#!/usr/bin/env bash
# gh-settings.sh - GitHub repository settings as code (HUMAN ONLY; agents are denied).
# qs-alias: configurar-github
#
# Usage: gh-settings.sh [--diff | --apply [--prune]] [--repo owner/repo] [--config file]
#   --diff    (default) print the differences between .github/repo-settings.json and the live
#             state; changes nothing (only GET calls).
#   --apply   send only the differing settings: PATCH repo, PUT actions permissions, rulesets
#             matched by name (POST to create, PUT to update). A second run sends nothing.
#   --prune   with --apply, also delete rulesets that are not in the JSON.
#   --repo    owner/repo; default: parsed from `git remote get-url origin` (must be GitHub).
#   --config  settings file; default: <suite>/.github/repo-settings.json.
# Credentials: only gh's own store (`gh auth login`). This script never reads or writes a
# token file and refuses to run when GH_TOKEN / GITHUB_TOKEN holds a value found in a tracked
# file. Exit: 0 ok, 1 refused or failed, 2 usage.
set -euo pipefail
SUITE="${QUALITY_SUITE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Print an error and stop. Arguments: message. Returns: never (exit 1).
die() {
	echo "[gh-settings] $*" >&2
	exit 1
}

# Print the usage header (the leading comment block) and stop. Arguments: exit code.
usage() {
	sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
	exit "${1:-2}"
}

# Derive owner/repo from a GitHub remote URL (https or ssh form).
# Arguments: url. Output: owner/repo on stdout. Returns: 0, or 1 when not a GitHub URL.
repo_from_url() {
	local u="$1"
	case "$u" in
	https://github.com/* | http://github.com/*) u="${u#*://github.com/}" ;;
	git@github.com:*) u="${u#git@github.com:}" ;;
	ssh://git@github.com/*) u="${u#ssh://git@github.com/}" ;;
	*) return 1 ;;
	esac
	u="${u%.git}"
	u="${u%/}"
	[[ $u =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
	printf '%s\n' "$u"
}

# Refuse when GH_TOKEN / GITHUB_TOKEN holds a value that appears in a tracked file.
# Arguments: none. Returns: 0 when fine; exits 1 (via die) otherwise.
check_token_source() {
	local tok
	for tok in "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}"; do
		[ -n "$tok" ] || continue
		if git grep -qF -f <(printf '%s\n' "$tok") 2>/dev/null; then
			die "refusing: GH_TOKEN/GITHUB_TOKEN comes from a tracked file. Unset it and use 'gh auth login'."
		fi
	done
}

mode="diff" prune=0 repo="" config="$SUITE/.github/repo-settings.json"
while [ $# -gt 0 ]; do
	case "$1" in
	--diff) mode="diff" ;;
	--apply) mode=apply ;;
	--prune) prune=1 ;;
	--repo)
		[ $# -ge 2 ] || usage 2
		repo="$2"
		shift
		;;
	--config)
		[ $# -ge 2 ] || usage 2
		config="$2"
		shift
		;;
	-h | --help) usage 0 ;;
	*) usage 2 ;;
	esac
	shift
done
[ "$prune" = 0 ] || [ "$mode" = apply ] || die "--prune needs --apply"
[ -f "$config" ] || die "settings file not found: $config"
command -v gh >/dev/null 2>&1 || die "gh is not installed (see docs/GITHUB.md for the manual steps)"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
check_token_source
if [ -z "$repo" ]; then
	url="$(git remote get-url origin 2>/dev/null)" || die "no 'origin' remote; use --repo owner/repo"
	repo="$(repo_from_url "$url")" || die "origin is not a GitHub URL: use --repo owner/repo"
fi
[[ $repo =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "bad --repo: $repo"

python3 -I - "$mode" "$prune" "$repo" "$config" <<'PY'
"""Compare .github/repo-settings.json with the live GitHub state through `gh api`."""
import json
import os
import subprocess
import sys

REPO_KEYS = {"default_branch": str, "allow_squash_merge": bool, "allow_merge_commit": bool,
             "allow_rebase_merge": bool, "delete_branch_on_merge": bool, "allow_auto_merge": bool,
             "allow_update_branch": bool, "has_wiki": bool, "has_projects": bool,
             "has_issues": bool, "has_discussions": bool, "squash_merge_commit_title": str,
             "squash_merge_commit_message": str}
SEC_KEYS = {"secret_scanning": bool, "secret_scanning_push_protection": bool,
            "dependabot_alerts": bool}
ACT_KEYS = {"allowed_actions": str, "github_owned_allowed": bool, "verified_allowed": bool,
            "patterns_allowed": list, "default_workflow_permissions": str,
            "can_approve_pull_request_reviews": bool, "fork_pr_approval": str}
RS_KEYS = {"name": str, "target": str, "enforcement": str, "include": list, "exclude": list,
           "rules": list, "bypass_actors": list}
RULES = {"deletion", "non_fast_forward", "creation", "update"}
DELIVERY_RULES = ("pull_request", "required_status_checks")
PR_PARAMS = {"required_approving_review_count": 0, "dismiss_stale_reviews_on_push": False,
             "require_code_owner_review": False, "require_last_push_approval": False,
             "required_review_thread_resolution": False}


def fail(msg):
    """Print an error and exit 1. Args: msg (str). Returns: never."""
    print("[gh-settings] " + msg, file=sys.stderr)
    sys.exit(1)


def check_section(name, data, keys):
    """Validate one object against a key/type table; unknown keys are refused.

    Args: name (str) section label; data (dict); keys (dict key -> type).
    Returns: None. Errors: exits 1 on an unknown key or a wrong type.
    """
    if not isinstance(data, dict):
        fail(name + " must be an object")
    for k, v in data.items():
        if k not in keys:
            fail("unknown key " + name + "." + k)
        if not isinstance(v, keys[k]):
            fail("wrong type for " + name + "." + k)


def load(path):
    """Load and validate the desired-state file. Args: path (str). Returns: dict. Errors: exit 1."""
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        fail("cannot read " + path + ": " + str(e))
    for k in d:
        if k not in ("repository", "security", "actions", "rulesets", "required_checks"):
            fail("unknown key " + k)
    rc = d.get("required_checks", [])
    if not isinstance(rc, list) or not all(isinstance(c, str) for c in rc):
        fail("required_checks must be a list of strings")
    check_section("repository", d.get("repository", {}), REPO_KEYS)
    check_section("security", d.get("security", {}), SEC_KEYS)
    check_section("actions", d.get("actions", {}), ACT_KEYS)
    names = set()
    for r in d.get("rulesets", []):
        check_section("rulesets[]", r, RS_KEYS)
        if set(r) != set(RS_KEYS):
            fail("ruleset " + str(r.get("name")) + " must define every key")
        if r["target"] not in ("branch", "tag") or not set(r["rules"]) <= RULES:
            fail("ruleset " + r["name"] + ": bad target or rule")
        if r["name"] in names:
            fail("duplicate ruleset " + r["name"])
        names.add(r["name"])
    return d


def gh(path, method="GET", body=None, tolerate=False):
    """Call `gh api`.

    Args: path; method; body (dict or None, sent on stdin); tolerate (bool: return None
    instead of failing). Returns: parsed JSON (or {}). Errors: exit 1 on failure.
    """
    cmd = ["gh", "api", "-X", method, path]
    data = None
    if body is not None:
        cmd += ["--input", "-"]
        data = json.dumps(body)
    p = subprocess.run(cmd, input=data, capture_output=True, text=True, check=False)
    if p.returncode != 0:
        if tolerate:
            return None
        fail("gh api " + method + " " + path + " failed: " + p.stderr.strip())
    return json.loads(p.stdout) if p.stdout.strip() else {}


def norm_ruleset(r):
    """Reduce a ruleset (desired or API form) to the compared shape. Returns: dict."""
    if "conditions" in r:
        ref = r.get("conditions", {}).get("ref_name", {})
        inc, exc = ref.get("include", []), ref.get("exclude", [])
        rules = [x["type"] for x in r.get("rules", [])]
        checks = [c["context"] for x in r.get("rules", [])
                  if x["type"] == "required_status_checks"
                  for c in x.get("parameters", {}).get("required_status_checks", [])]
    else:
        inc, exc, rules = r["include"], r["exclude"], r["rules"]
        checks = r.get("required_checks", [])
    return {"name": r["name"], "target": r["target"], "enforcement": r["enforcement"],
            "include": sorted(inc), "exclude": sorted(exc), "rules": sorted(rules),
            "required_checks": sorted(checks), "bypass_actors": r.get("bypass_actors", [])}


def read_delivery(config):
    """Read `branches.delivery` from quality-rules.json beside the settings file.

    Args: config (str) path of the settings file. Returns: 'auto', 'pr' or 'push' ('auto' when
    the file or the key is missing). Errors: exits 1 on an unreadable file or a bad value.
    """
    path = os.path.join(os.path.dirname(os.path.abspath(config)), "quality-rules.json")
    if not os.path.isfile(path):
        return "auto"
    try:
        with open(path, encoding="utf-8") as f:
            value = json.load(f).get("branches", {}).get("delivery", "auto")
    except (OSError, ValueError, AttributeError) as e:
        fail("cannot read " + path + ": " + str(e))
    if value not in ("auto", "pr", "push"):
        fail("branches.delivery must be auto, pr or push in " + path)
    return value


def apply_delivery(r, delivery, required, live_rules):
    """Apply the delivery policy to the `mainline` ruleset.

    Args: r (dict desired ruleset); delivery (str); required (list of check contexts);
    live_rules (list of API rule objects, empty when the ruleset does not exist yet).
    Returns: (ruleset dict, kept): 'pr' adds the two pull request rules, 'push' adds none,
    'auto' keeps the live ones (kept = those API rule objects, sent back unchanged).
    """
    r = dict(r)
    if delivery == "pr":
        r["rules"] = list(r["rules"]) + list(DELIVERY_RULES)
        r["required_checks"] = list(required)
        return r, []
    kept = [x for x in live_rules if delivery == "auto" and x["type"] in DELIVERY_RULES]
    r["rules"] = list(r["rules"]) + [x["type"] for x in kept]
    r["required_checks"] = norm_ruleset({"name": "", "target": "branch", "enforcement": "",
                                         "conditions": {}, "rules": kept})["required_checks"]
    return r, kept


def rule_object(r, t):
    """Build one API rule. Args: r (dict desired ruleset); t (str rule type). Returns: dict."""
    if t == "pull_request":
        return {"type": t, "parameters": dict(PR_PARAMS)}
    if t == "required_status_checks":
        return {"type": t, "parameters": {
            "strict_required_status_checks_policy": False,
            "required_status_checks": [{"context": c} for c in r.get("required_checks", [])]}}
    return {"type": t}


def ruleset_body(r, kept=()):
    """Build the API payload of a desired ruleset.

    Args: r (dict); kept (live rule objects to send as they are). Returns: dict.
    """
    keep = {x["type"]: x for x in kept}
    return {"name": r["name"], "target": r["target"], "enforcement": r["enforcement"],
            "conditions": {"ref_name": {"include": r["include"], "exclude": r["exclude"]}},
            "rules": [keep.get(t) or rule_object(r, t) for t in r["rules"]],
            "bypass_actors": r["bypass_actors"]}


def plan(repo, want, delivery):
    """Read the live state and build the changes.

    Args: repo (str owner/repo); want (dict); delivery (str auto|pr|push).
    Returns: (lines, calls): human diff lines and a list of (method, path, body) write calls, containing only what differs.
    """
    base = "repos/" + repo
    lines, calls = [], []

    def note(key, cur, new):
        """Record one difference line."""
        lines.append("  " + key + ": " + json.dumps(cur) + " -> " + json.dumps(new))

    live = gh(base)
    patch = {}
    for k, v in want.get("repository", {}).items():
        if live.get(k) != v:
            note("repository." + k, live.get(k), v)
            patch[k] = v
    sa = live.get("security_and_analysis") or {}
    for k, v in want.get("security", {}).items():
        if k == "dependabot_alerts":
            cur = gh(base + "/vulnerability-alerts", tolerate=True) is not None
            if cur != v:
                note("security." + k, cur, v)
                calls.append(("PUT" if v else "DELETE", base + "/vulnerability-alerts", None))
            continue
        cur = (sa.get(k) or {}).get("status") == "enabled"
        if cur != v:
            note("security." + k, cur, v)
            patch.setdefault("security_and_analysis", {})[k] = {
                "status": "enabled" if v else "disabled"}
    if patch:
        calls.insert(0, ("PATCH", base, patch))
    plan_actions(base, want.get("actions", {}), note, calls)
    plan_rulesets(base, want, note, calls, delivery)
    return lines, calls


def plan_actions(base, act, note, calls):
    """Plan the Actions policy calls.

    Args: base (str repos/o/r); act (dict desired actions); note (callback); calls (list,
    appended). Returns: None.
    """
    p = base + "/actions/permissions"
    cur = gh(p)
    if "allowed_actions" in act and cur.get("allowed_actions") != act["allowed_actions"]:
        note("actions.allowed_actions", cur.get("allowed_actions"), act["allowed_actions"])
        calls.append(("PUT", p, {"enabled": cur.get("enabled", True),
                                 "allowed_actions": act["allowed_actions"]}))
    sel = {k: act[k] for k in ("github_owned_allowed", "verified_allowed", "patterns_allowed")
           if k in act}
    if sel and act.get("allowed_actions") == "selected":
        cs = gh(p + "/selected-actions")
        diff = {k: v for k, v in sel.items() if cs.get(k) != v}
        for k, v in diff.items():
            note("actions." + k, cs.get(k), v)
        if diff:
            calls.append(("PUT", p + "/selected-actions", {**{k: cs.get(k) for k in sel}, **diff}))
    wf = {k: act[k] for k in ("default_workflow_permissions", "can_approve_pull_request_reviews")
          if k in act}
    if wf:
        cw = gh(p + "/workflow")
        diff = {k: v for k, v in wf.items() if cw.get(k) != v}
        for k, v in diff.items():
            note("actions." + k, cw.get(k), v)
        if diff:
            calls.append(("PUT", p + "/workflow", {**{k: cw.get(k) for k in wf}, **diff}))
    if "fork_pr_approval" in act:
        cf = gh(p + "/fork-pr-contributor-approval")
        if cf.get("approval_policy") != act["fork_pr_approval"]:
            note("actions.fork_pr_approval", cf.get("approval_policy"), act["fork_pr_approval"])
            calls.append(("PUT", p + "/fork-pr-contributor-approval",
                          {"approval_policy": act["fork_pr_approval"]}))


def plan_rulesets(base, want_all, note, calls, delivery):
    """Plan ruleset calls, matched by name; `mainline` follows the delivery policy.

    Args: base; want_all (dict, the settings file); note; calls (appended; live rulesets
    missing from the JSON become ('PRUNE', path, None), sent as DELETE only with --prune);
    delivery (str auto|pr|push). Returns: None.
    """
    live = {r["name"]: r["id"] for r in gh(base + "/rulesets") or []}
    required = want_all.get("required_checks", [])
    for desired in want_all.get("rulesets", []):
        name, cur_api, kept, path = desired["name"], None, [], ""
        if name in live:
            path = base + "/rulesets/" + str(live.pop(name))
            cur_api = gh(path)
        r = desired
        if name == "mainline":
            r, kept = apply_delivery(desired, delivery, required,
                                     (cur_api or {}).get("rules", []))
            if delivery == "auto":
                print("[gh-settings] delivery auto: mainline pull request rules left as served")
        if cur_api is None:
            note("ruleset " + name, None, "create")
            calls.append(("POST", base + "/rulesets", ruleset_body(r, kept)))
            continue
        want, cur = norm_ruleset(r), norm_ruleset(cur_api)
        if cur != want:
            for k in want:
                if cur.get(k) != want[k]:
                    note("ruleset " + name + "." + k, cur.get(k), want[k])
            calls.append(("PUT", path, ruleset_body(r, kept)))
    for name, rid in live.items():
        note("ruleset " + name, "present, not in the JSON", "kept (--prune deletes)")
        calls.append(("PRUNE", base + "/rulesets/" + str(rid), None))


def main(mode, prune, repo, config):
    """Entry point.

    Args: mode ('diff'|'apply'); prune ('0'|'1'); repo; config path.
    Returns: None. Errors: exit 1 on any gh failure.
    """
    want = load(config)
    lines, calls = plan(repo, want, read_delivery(config))
    if not lines:
        print("[gh-settings] " + repo + ": no differences")
        return
    print("[gh-settings] " + repo + ": differences (live -> desired)")
    print("\n".join(lines))
    if mode != "apply":
        print("[gh-settings] nothing changed (use --apply to send them)")
        return
    sent = 0
    for method, path, body in calls:
        if method == "PRUNE":
            if prune != "1":
                continue
            method = "DELETE"
        gh(path, method, body)
        sent += 1
        print("[gh-settings] sent " + method + " " + path)
    print("[gh-settings] done: " + str(sent) + " call(s)")


main(*sys.argv[1:5])
PY
