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
# initial commit on branch develop, then cd into it. Sets CASE_REPO (a unique "$T/case-XXXX"
# folder; the bare origin is "$CASE_REPO.git"). When FLOW (squash or merge) is given it is
# written to branches.flow of the repo's rules file.
# Errors: exits 1 through fail when HOME, QS_HOME or GIT_CONFIG_GLOBAL is not under $T (the
# case would touch the real configuration), when the install or the first commit does not
# work.
case_sandbox() {
	local flow="${1:-}" name
	[ -n "${T:-}" ] || fail "case_sandbox: T is not set; run the cases through tests/hooks/run.sh"
	# why: a case run on its own must never write to the real global configuration
	for name in HOME QS_HOME GIT_CONFIG_GLOBAL; do
		case "${!name:-}" in
		"$T"/?*) ;;
		*) fail "case_sandbox: $name='${!name:-}' is not under $T; refusing to run" ;;
		esac
	done
	# why: mktemp gives a unique name; counting folders would also count the origin folders
	CASE_REPO="$(mktemp -d "$T/case-XXXX")" || fail "cannot create a case folder in $T"
	git init -q --bare "$CASE_REPO.git"
	git init -q -b develop "$CASE_REPO"
	cd "$CASE_REPO" || fail "cannot enter $CASE_REPO"
	git config user.email t@example.com
	git config user.name tester
	"$SUITE/install.sh" "$CASE_REPO" >/dev/null || fail "install in $CASE_REPO"
	git remote add origin "$CASE_REPO.git"
	printf '# sandbox\n' >README.md
	git add README.md
	# why: the rules file is created by the first commit
	git commit -q -m "chore: initial" || fail "initial commit in $CASE_REPO"
	if [ -n "$flow" ]; then
		python3 - "$flow" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("branches", {})["flow"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
	fi
	git push -q origin develop 2>/dev/null || fail "push develop in $CASE_REPO"
}

# plumb_commit WHERE BRANCH FILE TEXT SUBJECT: one commit that writes TEXT (plus a newline) into
# FILE on top of BRANCH, made with plumbing in the current case repo: no hook runs (the fixture
# stands for a commit someone else made). WHERE is local (only refs/heads/BRANCH moves), origin
# (only BRANCH on origin moves, on top of origin/BRANCH; origin/BRANCH is fetched) or both. A
# checked-out BRANCH gets its work tree reset to the new commit. Prints the commit id.
# Errors: exits 1 through fail when a step does not work.
plumb_commit() {
	local where="$1" b="$2" f="$3" text="$4" s="$5" parent idx blob tree c
	idx="$(git rev-parse --absolute-git-dir)/plumb.idx"
	parent="refs/heads/$b"
	[ "$where" != origin ] || parent="refs/remotes/origin/$b"
	blob="$(printf '%s\n' "$text" | git hash-object -w --stdin)" || fail "plumb_commit: blob of $f"
	if ! GIT_INDEX_FILE="$idx" git read-tree "$parent" ||
		! GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$f" ||
		! tree="$(GIT_INDEX_FILE="$idx" git write-tree)"; then
		fail "plumb_commit: tree for $f on $b"
	fi
	rm -f "$idx"
	c="$(git commit-tree "$tree" -p "$parent" -m "$s")" || fail "plumb_commit: commit $s"
	if [ "$where" != origin ]; then
		git update-ref "refs/heads/$b" "$c" || fail "plumb_commit: move $b"
		[ "$(git branch --show-current)" != "$b" ] || git reset -q --hard "$c"
	fi
	if [ "$where" != local ]; then
		git update-ref refs/plumb/tip "$c"
		git -C "$CASE_REPO.git" fetch -q --no-tags "$CASE_REPO" "+refs/plumb/tip:refs/heads/$b" || fail "plumb_commit: origin $b"
		git update-ref -d refs/plumb/tip
		git fetch -q origin || fail "plumb_commit: fetch"
	fi
	printf '%s\n' "$c"
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
