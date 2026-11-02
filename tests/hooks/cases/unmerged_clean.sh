#!/usr/bin/env bash
# Case: git limpiar-unmerged (scripts/git-unmerged.sh), acceptance criteria U1-U12.
# Runs under tests/hooks/run.sh, which exports SUITE and T and the isolated git settings.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails; case-lib.sh
# comes from the harness branch, so shellcheck cannot follow it here
# shellcheck disable=SC2015,SC1091
set -uo pipefail
. "$SUITE/tests/hooks/case-lib.sh"

# mkbranch NAME FILE TEXT: create branch NAME from develop with one commit that writes TEXT to
# FILE, push it to origin and go back to develop.
mkbranch() {
	git checkout -q -b "$1" develop || fail "branch $1"
	printf '%s\n' "$3" >"$2"
	git add "$2"
	git commit -q -m "chore: change $2" || fail "commit on $1"
	git push -q origin "$1" || fail "push $1"
	git checkout -q develop
}

# mkforeign NAME FILE TEXT: like mkbranch for a name the branch model rejects (feature/x): the
# commit is made on a scratch branch and origin's ref is written with plumbing, no hook involved.
mkforeign() {
	local sha
	mkbranch "unmerged/scratch-$$" "$2" "$3"
	sha="$(git rev-parse "unmerged/scratch-$$")"
	git --git-dir="$CASE_REPO.git" update-ref "refs/heads/$1" "$sha" || fail "origin ref $1"
	git push -q origin ":unmerged/scratch-$$" || fail "drop scratch on origin"
	git branch -q -D "unmerged/scratch-$$"
	git fetch -q origin
}

# squash_local BRANCH: bring the changes of BRANCH into local develop as one new commit (a squash).
squash_local() {
	git merge --squash "$1" >/dev/null || fail "squash $1"
	git commit -q -m "feat: squash $1" || fail "commit squash of $1"
}

# squash BRANCH: squash_local, then publish develop (the command judges against origin/develop).
squash() {
	squash_local "$1"
	git push -q origin develop || fail "push develop after squash of $1"
}

# run_unmerged ARGS...: run git limpiar-unmerged, keeping its output in $OUT and status in $RC.
run_unmerged() {
	RC=0
	OUT="$(git limpiar-unmerged "$@" 2>&1)" || RC=$?
}

# refs: print every ref with its tip.
refs() { git for-each-ref --format='%(refname) %(objectname)'; }

# --- U1 alias and manual
case_sandbox
git config alias.limpiar-unmerged >/dev/null && ok "U1 alias exists" || fail "U1 alias"
bash "$SUITE/scripts/qs-help.sh" limpiar-unmerged | grep -q 'git limpiar-unmerged \[-n\]' &&
	ok "U1 manual entry" || fail "U1 manual entry"

# --- U12 nothing archived
run_unmerged
[ "$RC" = 0 ] && grep -q 'nothing to clean' <<<"$OUT" && ok "U12 nothing to clean" || fail "U12: $RC $OUT"

# --- U2, U3, U4, U6, U7 states and preview
mkbranch unmerged/a a.txt A
mkbranch unmerged-20261102/b b.txt B
mkbranch unmerged/c c.txt C
mkforeign feature/x x.txt X
mkforeign 5.0.0-RC1/f/x y.txt Y
mkbranch unmerged/rel VERSION 9.9.9
mkbranch unmerged/p p.txt P
git checkout -q -b unmerged/readme develop
printf '# sandbox\n<!-- qs:version -->[badge 1]<!-- /qs:version -->\n' >README.md
printf '1.0\n' >CITATION.cff
git add README.md CITATION.cff
git commit -q -m "docs: badge" && git push -q origin unmerged/readme
git checkout -q -b unmerged/readme2 develop
printf '# sandbox\n<!-- qs:version -->[badge 2]<!-- /qs:version -->\nextra line\n' >README.md
git add README.md
git commit -q -m "docs: extra" && git push -q origin unmerged/readme2
git checkout -q develop
squash unmerged/a
squash unmerged-20261102/b
squash unmerged/c
# c only on origin
git branch -D unmerged/c >/dev/null
git fetch -q origin
git branch -D unmerged-20261102/b unmerged/rel unmerged/readme unmerged/readme2 unmerged/p >/dev/null 2>&1 || true
git fetch -q origin
before="$(refs)"
run_unmerged -n
after="$(refs)"
[ "$RC" = 0 ] || fail "U7 exit $RC: $OUT"
[ "$before" = "$after" ] && ok "U7 -n leaves refs untouched" || fail "U7 refs changed"
git ls-remote origin | grep -q 'refs/heads/unmerged/a' && ok "U7 origin untouched" || fail "U7 origin"
for b in unmerged/a unmerged-20261102/b unmerged/c; do
	grep -q "^integrated: $b\$" <<<"$OUT" && ok "U2/U3 $b integrated" || fail "U2/U3 $b: $OUT"
done
grep -q 'feature/x\|5.0.0-RC1' <<<"$OUT" && fail "U2 out-of-scope branch listed: $OUT"
ok "U2 only archived branches listed"
grep -q '^integrated: unmerged/rel$' <<<"$OUT" && grep -q '^integrated: unmerged/readme$' <<<"$OUT" &&
	ok "U4 release files ignored" || fail "U4 ignored: $OUT"
grep -q '^pending: unmerged/readme2$' <<<"$OUT" && grep -A1 '^pending: unmerged/readme2$' <<<"$OUT" | grep -q 'M README.md' &&
	ok "U4 extra README line is pending" || fail "U4 pending: $OUT"
grep -A1 '^pending: unmerged/p$' <<<"$OUT" | grep -q 'p.txt' && ok "U6 pending lists its file" || fail "U6 pending: $OUT"

# --- U6 conflict and no merge base
case_sandbox
printf 'one\n' >f.txt
git add f.txt && git commit -q -m "chore: f" && git push -q origin develop
mkbranch unmerged/conf f.txt branch-version
printf 'two\n' >f.txt
git add f.txt && git commit -q -m "chore: f2"
git checkout -q --orphan unmerged/orphan
git rm -rfq . 2>/dev/null
printf 'o\n' >o.txt
git add o.txt && git commit -q -m "chore: orphan" && git push -q origin unmerged/orphan
git checkout -q develop
run_unmerged -n
grep -q '^pending: unmerged/conf$' <<<"$OUT" && grep -q 'conflicts' <<<"$OUT" &&
	grep -q '^pending: unmerged/orphan$' <<<"$OUT" && grep -q 'no merge base' <<<"$OUT" &&
	ok "U6 conflict and no merge base are pending" || fail "U6 conflict: $OUT"

# --- U5 superseded
case_sandbox
git checkout -q -b unmerged/4.0.2/RELEASE develop
printf 'one\n' >r.txt
printf 'dropped later\n' >z.txt
git add r.txt z.txt && git commit -q -m "chore: r" && git push -q origin unmerged/4.0.2/RELEASE
git checkout -q -b unmerged/4.0.3/RELEASE unmerged/4.0.2/RELEASE
printf 'two\n' >r2.txt
git rm -q z.txt
git add r2.txt && git commit -q -m "chore: r2" && git push -q origin unmerged/4.0.3/RELEASE
git checkout -q develop
git checkout -q -b tmp-tag develop
printf 'T\n' >t.txt
printf '3.0.0\n' >VERSION
git add t.txt VERSION && git commit -q -m "chore: tagged" && git tag 3.0.0
git checkout -q develop && git branch -D tmp-tag >/dev/null
mkbranch unmerged/tt t.txt T
mkbranch unmerged/old o.txt old
squash unmerged/4.0.3/RELEASE
run_unmerged -n
grep -q '^integrated: unmerged/4.0.3/RELEASE$' <<<"$OUT" &&
	grep -q '^superseded by unmerged/4.0.3/RELEASE: unmerged/4.0.2/RELEASE$' <<<"$OUT" &&
	ok "U5 ancestor of an integrated branch" || fail "U5 ancestor: $OUT"
grep -q '^superseded by 3.0.0: unmerged/tt$' <<<"$OUT" && ok "U5 same content as a release tag" || fail "U5 tag: $OUT"
grep -q '^pending: unmerged/old$' <<<"$OUT" && ok "U5 unproven branch pending" || fail "U5 pending: $OUT"

# --- U8 confirmation and deletion
case_sandbox
mkbranch unmerged/a a.txt A
mkbranch unmerged/p p.txt P
squash unmerged/a
sha_a="$(git rev-parse unmerged/a)"
sha_p="$(git rev-parse unmerged/p)"
before="$(refs)"
RC=0
OUT="$(echo n | git limpiar-unmerged 2>&1)" || RC=$?
[ "$(refs)" = "$before" ] && ! grep -q '^\[unmerged\] deleted' <<<"$OUT" && ok "U8 answering n deletes nothing" || fail "U8 n: $OUT"
run_unmerged --yes
[ "$RC" = 0 ] || fail "U8 exit $RC: $OUT"
grep -q "deleted unmerged/a (was $sha_a)" <<<"$OUT" && ok "U8 prints the deleted hash" || fail "U8 line: $OUT"
git rev-parse -q --verify refs/heads/unmerged/a >/dev/null && fail "U8 local a kept"
git ls-remote origin refs/heads/unmerged/a | grep -q . && fail "U8 origin a kept"
git rev-parse -q --verify refs/heads/unmerged/p >/dev/null && git ls-remote origin refs/heads/unmerged/p | grep -q "$sha_p" &&
	ok "U8 pending kept" || fail "U8 pending lost"
git branch unmerged/a "$sha_a" && ok "U8 restore with git branch" || fail "U8 restore"

# --- U10 different local and origin tips
case_sandbox
mkbranch unmerged/d d.txt D
squash unmerged/d
git checkout -q unmerged/d
printf '# changed\n' >README.md
git add README.md && git commit -q -m "chore: local only"
git checkout -q develop
run_unmerged --yes
grep -q '^pending: unmerged/d$' <<<"$OUT" && git rev-parse -q --verify refs/heads/unmerged/d >/dev/null &&
	git ls-remote origin refs/heads/unmerged/d | grep -q . && ok "U10 divergent tips stay pending" || fail "U10: $OUT"

# --- U11 checked out in a worktree
case_sandbox
mkbranch unmerged/w w.txt W
squash unmerged/w
git worktree add -q "$T/wt-u11" unmerged/w
run_unmerged --yes
[ "$RC" = 0 ] && git rev-parse -q --verify refs/heads/unmerged/w >/dev/null && ! git ls-remote origin refs/heads/unmerged/w | grep -q . &&
	grep -q 'kept local unmerged/w' <<<"$OUT" && ok "U11 worktree branch kept locally, gone on origin" || fail "U11: $RC $OUT"
git worktree remove --force "$T/wt-u11"

# --- U9 atomic push with leases
case_sandbox
mkbranch unmerged/m1 m1.txt M1
mkbranch unmerged/m2 m2.txt M2
squash unmerged/m1
squash unmerged/m2
other="$T/other-u9"
git clone -q "$CASE_REPO.git" "$other"
(cd "$other" && git config user.email o@example.com && git config user.name other)
# why: the pause hook runs between the fetch and the confirmation, so there is no sleep and no race
export QS_UNMERGED_PAUSE_CMD="cd '$other' && git checkout -q unmerged/m2 && printf 'moved\n' >moved.txt && git add moved.txt && git commit -q -m 'chore: moved' && git push -q origin unmerged/m2"
RC=0
OUT="$(echo y | git limpiar-unmerged 2>&1)" || RC=$?
unset QS_UNMERGED_PAUSE_CMD
[ "$RC" = 1 ] && git ls-remote origin refs/heads/unmerged/m1 | grep -q . && git ls-remote origin refs/heads/unmerged/m2 | grep -q . &&
	git rev-parse -q --verify refs/heads/unmerged/m1 >/dev/null && grep -q 'rejected' <<<"$OUT" &&
	ok "U9 lease failure deletes nothing, exit 1" || fail "U9: $RC $OUT"

# --- hook: a stamped archive branch (prefix taken) passes pre-push
case_sandbox
mkbranch unmerged-20261102101500/s s.txt S
git ls-remote origin refs/heads/unmerged-20261102101500/s | grep -q . &&
	ok "stamped archive branch pushes through the hooks" || fail "stamped archive push"

# --- dependency bumps are real changes, not release lines
case_sandbox
cat >pom.xml <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>g</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>org.x</groupId>
      <artifactId>lib</artifactId>
      <version>1.0</version>
    </dependency>
  </dependencies>
</project>
XML
cat >package.json <<'JSON'
{
  "name": "app",
  "version": "1.0.0",
  "dependencies": {
    "left-pad": { "version": "1.0.0" }
  }
}
JSON
git add pom.xml package.json && git commit -q -m "chore: manifests" && git push -q origin develop
git checkout -q -b unmerged/dep develop
sed -i 's|<version>1.0</version>|<version>2.0</version>|' pom.xml
git commit -q -am "chore: bump lib" && git push -q origin unmerged/dep
git checkout -q -b unmerged/npmdep develop
sed -i 's|"1.0.0" }|"2.0.0" }|' package.json
git commit -q -am "chore: bump npm dep" && git push -q origin unmerged/npmdep
git checkout -q -b unmerged/ownver develop
sed -i 's|<version>1.0.0</version>|<version>1.1.0</version>|' pom.xml
sed -i 's|^  "version": "1.0.0"|  "version": "1.1.0"|' package.json
git commit -q -am "chore: own version" && git push -q origin unmerged/ownver
git checkout -q develop
run_unmerged -n
grep -q '^pending: unmerged/dep$' <<<"$OUT" && grep -q '^pending: unmerged/npmdep$' <<<"$OUT" &&
	ok "dependency bumps stay pending" || fail "dep bump: $OUT"
grep -q '^integrated: unmerged/ownver$' <<<"$OUT" && ok "project version bump is a release line" || fail "own version: $OUT"

# --- a squash that exists only locally proves nothing
case_sandbox
mkbranch unmerged/loc l.txt L
squash_local unmerged/loc
run_unmerged --yes
[ "$RC" != 0 ] && git rev-parse -q --verify refs/heads/unmerged/loc >/dev/null &&
	git ls-remote origin refs/heads/unmerged/loc | grep -q . && grep -q 'not contained in origin/develop' <<<"$OUT" &&
	ok "local-only squash deletes nothing" || fail "local-only squash: $RC $OUT"

# --- without origin the local develop is used, and the output says so
case_sandbox
git checkout -q -b unmerged/n develop
printf 'N\n' >n.txt
git add n.txt && git commit -q -m "chore: n"
git checkout -q develop
squash_local unmerged/n
git remote remove origin
run_unmerged -n
grep -q '^integrated: unmerged/n$' <<<"$OUT" && grep -q 'local develop only' <<<"$OUT" &&
	ok "no origin: local develop, said so" || fail "no origin: $OUT"
