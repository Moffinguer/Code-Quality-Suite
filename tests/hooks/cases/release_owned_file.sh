#!/usr/bin/env bash
# release_owned_file (scripts/git-flow-lib.sh): the two sets of release-owned files, the empty path,
# and the ref/tag helpers that the flow libraries now share with qs-common.sh.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# shellcheck source=scripts/git-flow-lib.sh
. "$SUITE/scripts/git-flow-lib.sh"
qs_policy_defaults

for f in VERSION CHANGELOG.md CITATION.cff; do
	release_owned_file "$f" && ok "$f is release-owned" || fail "$f not release-owned"
	release_owned_file "$f" --content && ok "$f is release-owned with --content" || fail "$f not owned with --content"
done
for f in README.md pom.xml sub/pom.xml package.json; do
	release_owned_file "$f" && fail "$f owned without --content" || ok "$f is not owned without --content"
	release_owned_file "$f" --content && ok "$f is release-owned with --content" || fail "$f not owned with --content"
done
release_owned_file src/Main.java --content && fail "source file owned" || ok "a source file is never owned"
release_owned_file "" --content && fail "empty path owned" || ok "an empty path is never owned"

declare -F tst_die >/dev/null 2>&1 || . "$SUITE/scripts/git-testing.sh"
out="$(tst_say hi 2>&1)"
[ "$out" = "[testing] hi" ] && ok "tst_say keeps the [testing] tag" || fail "tst_say: $out"
rc=0
out="$(tst_die boom 2>&1)" || rc=$?
[ "$rc" = 1 ] && [ "$out" = "[testing] boom" ] && ok "tst_die keeps tag and status" || fail "tst_die: rc=$rc $out"
[ -z "${QS_TAG:-}" ] && ok "tst_* does not leak QS_TAG" || fail "QS_TAG leaked: $QS_TAG"
