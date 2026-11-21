#!/usr/bin/env bash
# The qs-version merge driver (scripts/merge-version.sh) during a rebase. Only the rebase of a
# '<v>/RELEASE' with branches.flow = squash (git publicar, git subir) keeps the version of the
# commit replayed (the RELEASE side); that case is in publish_mainline.sh. Every other rebase
# keeps the 4.x rule, the new base wins: a final branch rebased onto its bumped ORIGINAL (git
# subir) takes the ORIGINAL's version, and git pull --rebase takes the version of origin.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

case_sandbox squash
# why: this case builds branches that must not be on origin yet (publish on create is off here)
export QS_PUBLISH=0
V=5.1.0
F="$V/700"
git np "$V" >/dev/null && git push -q origin "$V/ORIGINAL" 2>/dev/null || fail "tree $V"
git np 700 >/dev/null && git push -q origin "$F/ORIGINAL" 2>/dev/null || fail "OT 700"
git nr work >/dev/null || fail "nr work"
[ "$(git show "$F/ORIGINAL:VERSION")" = "$V" ] || fail "the version tree has no VERSION $V"

# --- a final branch rebased onto its bumped ORIGINAL keeps the ORIGINAL's version (4.x) --------
# why: the branch's own commit and the ORIGINAL both changed VERSION, so the driver runs
plumb_commit local "$F/work" VERSION 5.1.0-work "chore: branch version" >/dev/null
plumb_commit both "$F/ORIGINAL" VERSION 5.1.1 "chore(version): 5.1.1" >/dev/null
out="$(git subir 2>&1)" || fail "git subir of $F/work: $out"
git merge-base --is-ancestor "$F/ORIGINAL" "$F/work" && [ "$(git show "$F/work:VERSION")" = 5.1.1 ] &&
	ok "rebase of a final branch onto its bumped ORIGINAL: the ORIGINAL's version wins (4.x)" ||
	fail "final rebase kept $(git show "$F/work:VERSION"): $out"

# --- git pull --rebase keeps the version of origin (4.x) ---------------------------------------
plumb_commit origin "$F/work" VERSION 5.1.2-remote "chore: remote version" >/dev/null
plumb_commit local "$F/work" VERSION 5.1.2-local "chore: local version" >/dev/null
out="$(git pull -q --rebase origin "$F/work" 2>&1)" || fail "git pull --rebase: $out"
git merge-base --is-ancestor "origin/$F/work" "$F/work" && [ "$(git show "$F/work:VERSION")" = 5.1.2-remote ] &&
	ok "git pull --rebase: the version of origin (the new base) wins (4.x)" ||
	fail "pull --rebase kept $(git show "$F/work:VERSION"): $out"
