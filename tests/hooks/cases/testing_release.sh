#!/usr/bin/env bash
# Case: O7 through a real 'git release'. A TESTING with an undistributed commit is set aside as
# unmerged/...; a clean TESTING is deleted with its tree. Both come from a real 'git testing crear'.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

V=7.2.0
A=$V/300200/RF1 # the requirement whose TESTING keeps an undistributed commit
B=$V/300201/RF1 # the requirement whose TESTING is clean

# develop carries a Maven project like the release case of run.sh
printf '# Demo\n\nText.\n' >README.md
printf '<project>\n  <groupId>g</groupId>\n  <artifactId>a</artifactId>\n  <version>6.22.6</version>\n</project>\n' >pom.xml
git add README.md pom.xml
git commit -q -m "build: maven project" || fail "pom on develop"
git push -q origin develop 2>/dev/null || fail "push develop"
printf '%s\n  300200\n    RF1\n      a\n  300201\n    RF1\n      b\n' "$V" | git es --push >/dev/null 2>&1 || fail "release tree"

# real sandboxes, built by 'git testing crear' from one source each
git checkout -q "$A/a"
printf 'a = 1\n' >a.py
git add a.py
git commit -q -m "feat(a): add a" || fail "commit on a"
git checkout -q "$B/b"
printf 'b = 1\n' >b.py
git add b.py
git commit -q -m "feat(b): add b" || fail "commit on b"
git testing crear "$A/a" --nivel "$A" >/dev/null || fail "crear A"
git testing crear "$B/b" --nivel "$B" >/dev/null || fail "crear B"

# one undistributed commit on the TESTING of A
git checkout -q "$A/TESTING"
printf 't = 1\n' >t.py
git add t.py
git commit -q -m "feat: only on testing" || fail "commit on TESTING"
git checkout -q "$A/a"
git integra -m "feat(a): add a" >/dev/null 2>&1 || fail "integra a"
git checkout -q "$B/b"
git integra -m "feat(b): add b" >/dev/null 2>&1 || fail "integra b"
for rf in "$A" "$B"; do
	git checkout -q "$rf/ORIGINAL"
	out="$(git integra -m "feat(rf1): requirement RF1" 2>&1)" || fail "integra $rf: $out"
done
# why: under squash an OT ORIGINAL goes up through its OT release (git release), not git integra;
# the OT release sets aside the undistributed TESTING of its requirements (O7)
for ot in "${A%/*}" "${B%/*}"; do
	git checkout -q "$ot/ORIGINAL"
	git release --yes >>rel.out 2>&1 || {
		cat rel.out
		fail "OT release $ot"
	}
done
git checkout -q develop

git release --version "$V" --yes >>rel.out 2>&1 || {
	cat rel.out
	fail "git release"
}
git rev-parse -q --verify "unmerged/$A/TESTING" >/dev/null &&
	[ "$(git show "unmerged/$A/TESTING:t.py")" = "t = 1" ] &&
	ok "O7 release: TESTING with an undistributed commit is set aside as unmerged/..." || {
	cat rel.out
	fail "O7: the TESTING with a commit was not set aside"
}
git rev-parse -q --verify "$A/TESTING" >/dev/null && fail "O7: the old TESTING name is still there"
grep -q "feat: only on testing" rel.out && ok "O7 release: the warning names the commit" || fail "O7: no warning: $(cat rel.out)"
git rev-parse -q --verify "$B/TESTING" >/dev/null && fail "O7: the clean TESTING was kept"
git for-each-ref --format='%(refname:short)' refs/heads | grep -q "^unmerged/$B" && fail "O7: the clean TESTING was set aside"
ok "O7 release: a clean TESTING is deleted with the tree"
