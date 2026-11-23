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

# case_commit FILE TEXT SUBJECT [BODY]: write TEXT (plus a newline) into FILE, add it and commit
# it on the current branch of the case repo, with the hooks.
# Arguments: $1 file, $2 content, $3 commit subject, $4 optional commit body. Returns: 0.
# Errors: exits 1 through fail (naming the subject and the branch) when the commit is refused.
case_commit() {
	printf '%s
' "$2" >"$1"
	git add "$1"
	if [ -n "${4:-}" ]; then
		git commit -q -m "$3" -m "$4" || fail "commit '$3' on $(git branch --show-current)"
	else
		git commit -q -m "$3" || fail "commit '$3' on $(git branch --show-current)"
	fi
}

# case_flow_eval CODE | CMD [ARG...]: run in a subshell that has scripts/git-flow-lib.sh loaded
# with the policy of the current case repo (qs_policy_load, as the hooks do). A single argument
# is shell CODE and is eval'ed (it may set QS_* variables or chain commands); several arguments
# are a command with its arguments, run as given.
# Returns: the status of CODE or CMD; its output is printed.
case_flow_eval() {
	(
		# shellcheck source=/dev/null
		. "$SUITE/scripts/git-flow-lib.sh"
		qs_policy_load
		if [ "$#" -eq 1 ]; then eval "$1"; else "$@"; fi
	)
}

# case_state [NAMESPACE...]: print every ref under the NAMESPACEs (default refs/heads) with its
# object, then the current branch and the work tree status. Two prints that are equal prove
# that a refused or preview command changed nothing.
# Arguments: ref namespaces such as refs/heads refs/tags. Returns: 0.
case_state() {
	git for-each-ref --format='%(refname) %(objectname)' "${@:-refs/heads}"
	git branch --show-current
	git status --porcelain
}

# case_refused PATTERN CMD [ARG...]: the command must fail and its output (stdout and stderr)
# must contain PATTERN as a fixed string.
# Arguments: $1 text expected in the refusal, then the command. Returns: 0 when refused with the
# text. Errors: exits 1 through fail when the command succeeds or prints no PATTERN.
case_refused() {
	local word="$1" out
	shift
	if out="$("$@" 2>&1)"; then fail "not refused: $*"; fi
	grep -qF -- "$word" <<<"$out" || fail "refused without '$word': $* -> $out"
}

# case_squash_msg SUBJECT FILE: write the message git proposes for the pending squash
# (.git/SQUASH_MSG), under SUBJECT, into FILE.
# Arguments: $1 subject, $2 file. Returns: 0. Errors: exits 1 through fail when it cannot write.
case_squash_msg() {
	{
		printf '%s\n\n' "$1"
		cat .git/SQUASH_MSG
	} >"$2" || fail "cannot write the squash message"
}

# case_on_origin BRANCH: succeed when the branch exists on origin.
# Arguments: $1 branch name. Returns: 0 when it exists, 1 otherwise.
case_on_origin() { [ -n "$(git ls-remote --heads origin "refs/heads/$1")" ]; }

# case_local_has BRANCH: succeed when the local branch exists.
# Arguments: $1 branch name. Returns: 0 when it exists, 1 otherwise.
case_local_has() { git rev-parse -q --verify "refs/heads/$1" >/dev/null; }

# case_fresh_tree VERSION OT RF: a squash sandbox with the tree VERSION/OT/RF, one integrated
# branch a (local and on origin) and RF/ORIGINAL checked out and pushed.
# Arguments: $1 version, $2 OT name, $3 RF name (for example 9.0.0 500 RF1).
# Errors: exits 1 through fail when a step does not work.
case_fresh_tree() {
	local rf="$1/$2/$3"
	case_sandbox squash
	# why: the three np calls build the tree one level at a time; any failure aborts the case
	if ! { git np "$1" && git np "$2" && git np "$3"; } >/dev/null; then fail "tree $rf"; fi
	git nr a >/dev/null || fail "nr a"
	case_commit a.py 'A = 1' "feat: add a"
	git push -q origin "$rf/a" 2>/dev/null || fail "push a"
	git integra -m "feat: integrate a" -m "why a" >/dev/null 2>&1 </dev/null || fail "integra a"
	QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$rf/a" 2>/dev/null || fail "repush a"
	git checkout -q "$rf/ORIGINAL"
	QUALITY_SKIP_PARENT_CHECK=1 git push -q origin "$rf/ORIGINAL" 2>/dev/null || fail "push ORIGINAL"
	git fetch -q origin
}

# case_publish_tree VERSION: a fresh squash sandbox with the version tree VERSION created
# (git np) and VERSION/ORIGINAL pushed to origin; VERSION/ORIGINAL is checked out.
# Arguments: $1 version. Errors: exits 1 through fail when a step does not work.
case_publish_tree() {
	case_sandbox squash
	git np "$1" >/dev/null || fail "tree $1"
	git push -q origin "$1/ORIGINAL" 2>/dev/null || fail "push of the tree $1"
}

# case_testing_tree [PUSH]: in the current case repo, with F (the OT folder), ORIG ($F/ORIGINAL)
# and TST ($F/TESTING) set by the case, build an ORIGINAL with a shared file, a source branch
# $F/a with one commit, the TESTING branch made by 'git testing crear' and one commit of its
# own (t1.txt) on it; TESTING is left checked out. With PUSH (the word "push") the source is
# first merged into ORIGINAL and both are pushed to origin.
# Errors: exits 1 through fail when a step does not work.
case_testing_tree() {
	git checkout -q -b "$ORIG" develop
	case_commit shared.txt base "chore: shared file"
	git checkout -q -b "$F/a" "$ORIG"
	case_commit a.txt a "feat: a"
	git testing crear "$F/a" >/dev/null || fail "crear failed"
	if [ "${1:-}" = push ]; then
		git checkout -q "$ORIG"
		git merge -q --ff-only "$F/a" || fail "ff of ORIGINAL to a"
		git push -q origin "$ORIG" "$F/a" 2>/dev/null || fail "push of ORIGINAL and a"
	fi
	git checkout -q "$TST"
	case_commit t1.txt t1 "feat: t1"
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
