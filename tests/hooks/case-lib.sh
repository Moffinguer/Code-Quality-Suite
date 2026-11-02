#!/usr/bin/env bash
# Helpers shared by tests/hooks/run.sh and the case files in tests/hooks/cases/.
# run.sh exports SUITE (the suite checkout), T (the temp dir), the fake docker on PATH and
# the isolated git/HOME settings, then calls run_cases. A case file is run as its own bash
# process; it sources this file and uses ok, fail and case_sandbox.

# fail MESSAGE...: print "FAIL: <message>" to stderr and exit 1.
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# ok MESSAGE...: print "ok   <message>" to stdout.
ok() { echo "ok   $*"; }

# case_sandbox [FLOW]: create a fresh repo with the suite installed, a bare "origin" and an
# initial commit on branch develop, then cd into it. Sets CASE_REPO. When FLOW (squash or
# merge) is given it is written to branches.flow of the repo's rules file.
# Errors: exits 1 through fail when the install or the first commit does not work.
case_sandbox() {
	local flow="${1:-}" n
	n="$(find "$T" -maxdepth 1 -name 'case-*' | wc -l | tr -d ' ')"
	CASE_REPO="$T/case-$n"
	git init -q --bare "$CASE_REPO.git"
	git init -q -b develop "$CASE_REPO"
	cd "$CASE_REPO" || fail "cannot enter $CASE_REPO"
	git config user.email t@example.com
	git config user.name tester
	"$SUITE/install.sh" "$CASE_REPO" >/dev/null || fail "install in $CASE_REPO"
	git remote add origin "$CASE_REPO.git"
	if [ -n "$flow" ]; then
		python3 - "$flow" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("branches", {})["flow"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
	fi
	printf '# sandbox\n' >README.md
	git add README.md
	git commit -q -m "chore: initial" || fail "initial commit in $CASE_REPO"
	git push -q origin develop 2>/dev/null || fail "push develop in $CASE_REPO"
}

# run_cases DIR: run every DIR/*.sh in name order, each as its own bash process. Stops at the
# first failing case, printing "FAIL: case <name>" and exiting 1. An empty or missing DIR is
# fine. Returns 0 when every case passed.
run_cases() {
	local dir="$1" f name
	[ -d "$dir" ] || return 0
	for f in "$dir"/*.sh; do
		[ -e "$f" ] || continue
		name="$(basename "$f")"
		echo "case $name"
		bash "$f" || fail "case $name"
	done
	return 0
}
