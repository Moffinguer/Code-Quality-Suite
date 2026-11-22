#!/usr/bin/env bash
# main_branch.sh - initial branch (AGENTS section 4.13, MB1-MB3): git iniciar makes an empty root
# commit on main, develop at that commit, HEAD on develop; it never writes init.defaultBranch, even
# when the global default is master; an existing repository with master and no main gets one
# warning and is not renamed; with main there is no warning. Standalone: its own HOME, global git
# config and temporary folders, and the fake docker of tests/hooks/fake-docker.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
SUITE="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export FAKE_DOCKER_DIR="$T/docker" QS_SUITE_HOST="$SUITE" QS_NO_PROMPT=1 QS_REPO_FILES=0
# why: the global default is master here, so a suite that followed it would fail (MB2); the
# identity is set so that commits made by the test and by git iniciar work
export GIT_CONFIG_GLOBAL="$T/gitconfig" QS_HOME="$T/qs-home"
printf '[init]\n\tdefaultBranch = master\n[user]\n\tname = tester\n\temail = t@example.com\n' >"$GIT_CONFIG_GLOBAL"
cp "$GIT_CONFIG_GLOBAL" "$T/gitconfig.before"
export HOME="$T/home"
mkdir -p "$HOME" "$T/bin"
ln -s "$SUITE/tests/hooks/fake-docker" "$T/bin/docker"
export PATH="$T/bin:$PATH"
# the empty tree of a SHA-1 repository
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok   $*"; }

# MB1: a new project from an empty folder
bash "$SUITE/scripts/qs-init.sh" --sin-ia "$T/new" >"$T/new.out" 2>&1 || {
	cat "$T/new.out" >&2
	fail "git iniciar on a new folder"
}
N="$T/new"
[ "$(git -C "$N" symbolic-ref --short HEAD)" = develop ] && ok "HEAD on develop" || fail "HEAD is not develop"
[ "$(git -C "$N" rev-parse --verify -q refs/heads/main)" = "$(git -C "$N" rev-parse --verify -q refs/heads/develop)" ] &&
	ok "main and develop point to the same commit" || fail "main and develop differ"
[ "$(git -C "$N" rev-list --count main)" = 1 ] && ok "one commit: the empty root commit" || fail "not one commit"
[ "$(git -C "$N" log -1 --format=%s main)" = "chore: initial commit" ] && ok "root commit subject" || fail "root subject"
[ "$(git -C "$N" log -1 --format=%T main)" = "$EMPTY_TREE" ] && ok "root commit has the empty tree" || fail "root tree"
[ -z "$(git -C "$N" log -1 --format=%P main)" ] && ok "root commit has no parent" || fail "root has a parent"
grep -q 'branches main and develop' "$T/new.out" && ok "message names main and develop" || fail "message"
grep -q 'git push -u origin main develop' "$T/new.out" && ok "next step pushes main and develop" || fail "next step"

# MB2: the suite does not write init.defaultBranch, globally or locally
[ -z "$(git -C "$N" config --local --get init.defaultBranch || true)" ] && ok "no local init.defaultBranch" ||
	fail "local init.defaultBranch written"
cmp -s "$GIT_CONFIG_GLOBAL" "$T/gitconfig.before" && ok "global config untouched" || fail "global config changed"

# MB3: an existing repository with master only is warned about, not renamed
git init -q -b master "$T/old"
git -C "$T/old" commit -q --allow-empty -m "chore: start" || fail "commit in the master repository"
bash "$SUITE/scripts/qs-init.sh" --sin-ia "$T/old" >"$T/old.out" 2>&1 || {
	cat "$T/old.out" >&2
	fail "git iniciar on an existing repository"
}
[ "$(grep -c 'principal branch is master' "$T/old.out")" = 1 ] && ok "one warning for master only" ||
	fail "warning for master missing or repeated"
[ "$(git -C "$T/old" symbolic-ref --short HEAD)" = master ] && ! git -C "$T/old" show-ref --verify -q refs/heads/main &&
	ok "master not renamed, no main created" || fail "master was renamed or main created"

# MB3: with main there is no warning (bootstrap alone, as git instalar and git clonar run it)
git init -q -b main "$T/withmain"
git -C "$T/withmain" commit -q --allow-empty -m "chore: start" || fail "commit in the main repository"
bash "$SUITE/bootstrap.sh" "$T/withmain" >"$T/withmain.out" 2>&1 || {
	cat "$T/withmain.out" >&2
	fail "bootstrap on a main repository"
}
! grep -q 'principal branch is master' "$T/withmain.out" && ok "no warning when main exists" ||
	fail "warning printed although main exists"
echo "all main branch checks passed"
