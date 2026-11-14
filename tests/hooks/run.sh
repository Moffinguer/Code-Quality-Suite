#!/usr/bin/env bash
# End-to-end test of install.sh + hooks with a fake docker CLI (tests/hooks/fake-docker):
# commit formats and stages, marks scripts, creates/ignores the rules file, logs, applies
# rule changes, blocks broken code; push verifies in check mode.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
[ "${QS_TEST_DEBUG:-0}" = 1 ] && set -x
SUITE="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export SUITE T
export FAKE_DOCKER_DIR="$T/docker" QS_SUITE_HOST="$SUITE" QS_NO_PROMPT=1 QS_REPO_FILES=0
# why: never touch the real global git config or the real list of installed repositories
export GIT_CONFIG_GLOBAL="$T/gitconfig" QS_HOME="$T/qs-home"
: >"$GIT_CONFIG_GLOBAL"
# why: setup-global writes ~/.bashrc and the clone template under HOME
export HOME="$T/home"
mkdir -p "$HOME"
mkdir -p "$T/bin"
ln -s "$SUITE/tests/hooks/fake-docker" "$T/bin/docker"
export PATH="$T/bin:$PATH"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

git init -q -b main "$T/repo"
cd "$T/repo"
git config user.email t@example.com
git config user.name tester
"$SUITE/install.sh" "$T/repo" >/dev/null
[ -x .git/hooks/pre-commit ] && ok "hooks installed" || fail "hooks"

printf 'import os\ndef f( a ):\n    return os.path.join(a,"x")   \n' >app.py
printf 'echo "hi"\n' >run.sh
chmod +x run.sh
printf 'select a from t\n' >q.sql
git add app.py run.sh q.sql
git commit -q -m "feat: add sample files" || fail "first commit was blocked"
ok "first commit"
git show HEAD:app.py | grep -q 'def f(a):' && ok "formatting committed" || fail "app.py not formatted in the commit"
git show HEAD:run.sh | head -1 | grep -q '^#!/usr/bin/env bash' && ok "shebang committed" || fail "no shebang"
git show HEAD:q.sql | grep -q '^SELECT a' && ok "SQL formatted" || fail "sql"
[ -f .quality-rules.json ] && ok "rules file created" || fail "no rules file"
git status --porcelain --ignored | grep -q '^!! .quality-rules.json' && ok "rules file ignored" || fail "rules file not ignored"
grep -q 'action=ruff-format status=SUCCESS' .git/quality-suite/quality-suite.log && ok "per-tool log" || fail "log"
grep -q 'qs.langs=_global' "$FAKE_DOCKER_DIR/calls.log" && grep -q 'python' "$FAKE_DOCKER_DIR/calls.log" &&
	ok "on-demand install layer" || fail "no install layer"

python3 - <<'PY'
import json; p='.quality-rules.json'; d=json.load(open(p))
d['languages']['python']['formatting']['ruff-format']['rules']['line-length'] = 120
json.dump(d, open(p, 'w'), indent=2)
PY
printf 'x = 1\n' >b.py
git add b.py
git commit -q -m "feat: second file" || fail "second commit"
grep -q 'modified languages.python.formatting.ruff-format.rules.line-length: 100 -> 120' .git/quality-suite/quality-suite.log &&
	ok "rule change logged" || fail "rule change not logged"
grep -q 'line-length = 120' .git/quality-suite/generated/python/ruff/ruff.toml && ok "native config regenerated (inherited by lint)" ||
	fail "generated config"

printf 'def broken(:\n  pass\n' >bad.py
git add bad.py
if git commit -q -m "feat: broken" 2>/dev/null; then fail "broken code was committed"; else ok "broken code blocked"; fi
git reset -q HEAD bad.py
rm bad.py

# partial staging: the unstaged edit must neither be committed nor lost
body='def g():\n    return 1\n\n\ndef h():\n    return 3\n\n\ndef i():\n    return 4\n\n\ndef j():\n    return 5\n'
# shellcheck disable=SC2059
printf "$body" >part.py
git add part.py
git commit -q -m "feat: part" || fail "part commit"
# shellcheck disable=SC2059
printf "${body/return 1/return  2}" >part.py
git add part.py
# shellcheck disable=SC2059
printf "${body/return 1/return  2}SECRET_DEBUG = True\n" >part.py
git commit -q -m "fix: partial" || fail "partial commit"
git show HEAD:part.py | grep -q SECRET_DEBUG && fail "unstaged edit was committed" || ok "unstaged edit not committed"
grep -q SECRET_DEBUG part.py && ok "unstaged edit kept in the working tree" || fail "unstaged edit lost"
git show HEAD:part.py | grep -q '    return 2' && ok "staged part formatted" || fail "staged part not formatted"
git checkout -q -- part.py
# overlap: the formatter changes the very lines next to the unstaged edit -> nothing changes
printf 'def k():\n    return  1\n' >near.py
git add near.py
printf 'def k():\n    return  1\nNEAR = 1\n' >near.py
before="$(cat near.py)"
if git commit -q -m "feat: near" 2>/dev/null; then fail "overlapping partial commit went through"; fi
[ "$(cat near.py)" = "$before" ] && ok "overlap: working tree untouched" || fail "overlap changed the working tree"
git show :near.py | grep -q 'return  1' && ok "overlap: index untouched" || fail "overlap changed the index"
git reset -q HEAD near.py
rm -f near.py

# accents in file names
printf 'x=1\n' >"configuración.py"
git add "configuración.py"
git commit -q -m "feat: accent" || fail "accent commit"
git show "HEAD:configuración.py" | grep -q '^x = 1' && ok "accented file name checked" || fail "accented file skipped"

# encoding: text damaged by a wrong-encoding save stops the commit and names the files
printf 'msg = "Canci\303\263n"\n' >enc.py
git add enc.py
git commit -q -m "feat: enc" || fail "enc commit"
printf 'msg = "Canci\303\203\302\263n"\nx = 1\n' >enc.py # UTF-8 read as Windows-1252, saved as UTF-8
printf 'a = "a\361o"\n' >ansi.py                         # saved as Windows-1252 (ANSI)
git add enc.py ansi.py
out="$(git commit -m 'fix: enc' 2>&1)" && fail "mojibake committed"
printf '%s\n' "$out" | grep -q 'ENCODING: 2 file(s)' && printf '%s\n' "$out" | grep -q "should be \"Canci$(printf '\303\263')n\"" &&
	printf '%s\n' "$out" | grep -q 'ansi.py' && ok "mojibake and ANSI files stop the commit, listed by name" ||
	fail "encoding report: $out"
printf '%s\n' "$out" | grep -q 'ruff' && fail "tools ran on an encoding failure" || ok "nothing analysed after an encoding failure"
out="$(git encoding 2>&1)" && fail "git encoding passed"
printf '%s\n' "$out" | grep -q 'enc.py' && ok "git encoding lists the changed files" || fail "git encoding: $out"
git encoding --fix >/dev/null 2>&1 || fail "git encoding --fix"
grep -q "$(printf 'Canci\303\263n')" enc.py && grep -q "$(printf 'a\303\261o')" ansi.py && ok "git encoding --fix repaired both" ||
	fail "repair: $(cat enc.py ansi.py)"
git add enc.py ansi.py
git commit -q -m "fix: enc" || fail "commit after the repair"
# a commit with no recognised language still runs the repository checks
# why split: the literal would make the repository checks reject this very file
printf -- '-----BEGIN RSA PRIVATE ''KEY-----\nabc\n-----END RSA PRIVATE ''KEY-----\n' >id_key
git add id_key
if git commit -q -m "feat: key" 2>/dev/null; then fail "private key committed"; else ok "private key blocked"; fi
git reset -q HEAD id_key
rm -f id_key

git init -q --bare "$T/remote.git"
git remote add origin "$T/remote.git"
git push -q origin main 2>/dev/null && ok "push verified in check mode" || fail "push"
# damage already committed (and pushed) only warns: the commit and the push touch another line
printf 'old = "Canci\303\203\302\263n"\n' >legacy.py
git add legacy.py
# why plumbing: the legacy commit is made with commit-tree and update-ref (no hook runs), and the
# bare origin gets it by a fetch from this repository, so no push hook runs either
legacy="$(git commit-tree "$(git write-tree)" -p "$(git rev-parse HEAD)" -m "feat: legacy")" || fail "legacy commit"
git update-ref refs/heads/main "$legacy" "$(git rev-parse HEAD)" || fail "legacy commit ref"
git --git-dir="$T/remote.git" fetch -q "$T/repo" main:main || fail "legacy push"
printf 'old = "Canci\303\203\302\263n"\ny = 2\n' >legacy.py
git add legacy.py
out="$(git commit -m 'fix: legacy' 2>&1)" || fail "pre-existing mojibake blocked the commit: $out"
printf '%s\n' "$out" | grep -q 'WARN encoding legacy.py.*already in HEAD' && ok "pre-existing mojibake only warns" ||
	fail "no warning: $out"
git push -q origin main 2>/dev/null && ok "push: damage already on the remote only warns" || fail "legacy push blocked"
grep -q 'comp=pre-push.*status=SUCCESS' .git/quality-suite/quality-suite.log && ok "push logged" || fail "push log"

# push checks the committed tree, not the working tree
printf 'def broken(:\n  pass\n' >late.py
git add late.py
# why plumbing: the broken commit is made with commit-tree and update-ref, so no commit hook runs
late="$(git commit-tree "$(git write-tree)" -p "$(git rev-parse HEAD)" -m "feat: late")" || fail "late commit"
git update-ref refs/heads/main "$late" "$(git rev-parse HEAD)" || fail "late commit ref"
printf 'x = 1\n' >late.py # fixed only in the working tree
if git push -q origin main 2>/dev/null; then fail "broken commit was pushed"; else ok "push checks the committed content"; fi
git reset -q --hard HEAD~1

# CI: a missing base fails loudly
if QUALITY_SUITE_DIR="$SUITE" "$SUITE/scripts/ci-check.sh" origin/does-not-exist >/dev/null 2>&1; then
	fail "ci-check passed without a base"
else ok "ci-check fails without its base"; fi
# commit message policy: ASCII only by default (commit.charset)
printf 'y = 2\n' >cm.py
git add cm.py
if git commit -q -m "feat: añadir validación" 2>/dev/null; then fail "non-ASCII commit message accepted"; else ok "non-ASCII commit message blocked"; fi
git commit -q -m "feat: anadir validacion" || fail "ASCII message rejected"
ok "ASCII commit message accepted"

# encoding policy: every text file must be UTF-8 (encoding.charset)
printf 'A\xf1o = 1\n' >latin.txt
git add latin.txt
if git commit -q -m "feat: latin" 2>/dev/null; then fail "non-UTF-8 file committed"; else ok "non-UTF-8 file blocked"; fi
git reset -q HEAD latin.txt
rm -f latin.txt
python3 - <<'PY'
import json; p='.quality-rules.json'; d=json.load(open(p))
d['encoding']['by_glob'] = {'legacy/*.properties': 'iso-8859-1'}
# why: the 4.x regression suite below is pinned to the merge flow
d.setdefault('branches', {})['flow'] = 'merge'
json.dump(d, open(p, 'w'), indent=2)
PY
mkdir -p legacy
printf 'msg=Espa\xf1a\n' >legacy/m.properties
git add legacy/m.properties
git commit -q -m "feat: legacy properties" || fail "declared ISO-8859-1 file rejected"
git show HEAD:legacy/m.properties | od -An -tx1 | grep -q f1 && ok "legacy charset kept byte-exact" || fail "legacy file altered"

# branch model: <version>/<ot>/.../ORIGINAL, final branches beside it (git aliases)
export GIT_EDITOR="sed -i.bak -e s/DESCRIPCION_BREVE/integrate/"
git checkout -q -b develop && git push -q origin develop 2>/dev/null || fail "push develop"
git np 6.22.6 >/dev/null && [ "$(git branch --show-current)" = 6.22.6/ORIGINAL ] && ok "git np: version branch" || fail "np version"
# text OT: ASCII letters and digits (branches.levels[1]); numeric OTs keep working below
git np ABC123 >/dev/null && [ "$(git branch --show-current)" = 6.22.6/ABC123/ORIGINAL ] && git nr login >/dev/null &&
	[ "$(git branch --show-current)" = 6.22.6/ABC123/login ] && ok "git np/nr: text OT ABC123" || fail "text OT refused"
(
	# shellcheck source=/dev/null
	. "$SUITE/scripts/git-flow-lib.sh" && qs_policy_load && export QS_BR_TAG='{version}-{ot}' &&
		[ "$(render_tag 6.22.6/ABC123/ORIGINAL)" = 6.22.6-ABC123 ]
) && ok "tag {version}-{ot} with a text OT" || fail "render_tag text OT"
git checkout -q 6.22.6/ORIGINAL
before_bad="$(git for-each-ref --format='%(refname:short)' refs/heads)"
for bad in "AB 12" "A$(printf '\303\221')O1" "" AB-12 AB_12 RELEASE ORIGINAL; do
	if git np "$bad" >/dev/null 2>&1; then fail "OT '$bad' accepted"; else ok "OT '$bad' refused"; fi
done
if git nr RELEASE >/dev/null 2>&1; then fail "git nr RELEASE accepted"; else ok "git nr RELEASE refused"; fi
[ "$(git for-each-ref --format='%(refname:short)' refs/heads)" = "$before_bad" ] && ok "refused OTs created nothing" || fail "refused OT created a branch"
if (git checkout -q develop && git np ABC123 >/dev/null 2>&1); then fail "text name accepted as a version"; else ok "git np ABC123 from develop refused"; fi
git checkout -q 6.22.6/ORIGINAL
git np 188858 >/dev/null && git np RF001 >/dev/null || fail "np nested"
git nr login >/dev/null
printf 'L = 1\n' >login.py
git add login.py
git commit -q -m "feat: login" || fail "commit login"
if git nr sub 2>/dev/null; then fail "final branch got a child"; else ok "final branch cannot have children"; fi
git checkout -q 6.22.6/188858/RF001/ORIGINAL && git nr bank >/dev/null
printf 'B = 1\n' >bank.py
git add bank.py
git commit -q -m "feat: bank" || fail "commit bank"
git push -q origin 6.22.6/188858/RF001/bank 2>/dev/null || fail "push final branch"
git convertir-padre --yes >/dev/null 2>&1 && [ "$(git branch --show-current)" = 6.22.6/188858/RF001/bank/ORIGINAL ] &&
	git ls-remote --heads origin | grep -q 'RF001/bank/ORIGINAL$' && ! git ls-remote --heads origin | grep -q 'RF001/bank$' &&
	ok "convertir-padre renames local and remote" || fail "convertir-padre"
git nr bugfix >/dev/null
printf 'F = 1\n' >fix.py
git add fix.py
git commit -q -m "fix: bank bug" || fail "commit bugfix"
git integra >/dev/null 2>&1 && [ "$(git branch --show-current)" = 6.22.6/188858/RF001/bank/ORIGINAL ] &&
	git log -1 --format=%s | grep -q '^feat(bugfix): integrate' && ok "integra: final -> its ORIGINAL" || fail "integra final"
git checkout -q 6.22.6/188858/RF001/ORIGINAL
if git integra >/dev/null 2>&1; then fail "integrated with pending children"; else ok "integra waits for the children"; fi
git checkout -q 6.22.6/188858/RF001/bank/ORIGINAL && git integra >/dev/null 2>&1 || fail "integra bank"
git checkout -q 6.22.6/188858/RF001/login && git integra >/dev/null 2>&1 || fail "integra login (rebase + merge)"
git integra >/dev/null 2>&1 && git integra >/dev/null 2>&1 || fail "integra RF001 -> OT -> version"
[ "$(git branch --show-current)" = 6.22.6/ORIGINAL ] || fail "expected to be on 6.22.6/ORIGINAL"
git integra >/dev/null 2>&1 && [ "$(git branch --show-current)" = develop ] && git rev-parse -q --verify refs/tags/6.22.6 >/dev/null &&
	git show develop:fix.py >/dev/null && git show develop:login.py >/dev/null && ok "version ORIGINAL tagged and merged into develop" ||
	fail "version -> develop"
# why: hooksPath is part of the check - the shared-ORIGINAL rebase guard must be active
if QUALITY_ALLOW_REBASE=0 git -c core.hooksPath=.git/hooks rebase 6.22.6/188858/ORIGINAL 6.22.6/ORIGINAL >/dev/null 2>&1; then
	fail "shared ORIGINAL was rebased"
else
	git rebase --abort >/dev/null 2>&1 || true
	ok "shared ORIGINAL cannot be rebased"
fi
git checkout -q develop
git checkout -q -b mi-rama
if git push -q origin mi-rama 2>/dev/null; then fail "off-model branch pushed"; else ok "off-model branch name blocked on push"; fi
git checkout -q develop
tree="$(git arbol 6.22.6)"
grep -q '   + 6.22.6/188858/ORIGINAL' <<<"$tree" && ok "git arbol" || fail "arbol: $tree"
# agents in their own worktree (Claude Code isolation: worktree, branch worktree-<name>)
git np 6.22.7 >/dev/null && git np 200001 >/dev/null || fail "np for the worktree test"
git worktree add -q -b worktree-agent1 ../wt HEAD >/dev/null 2>&1 || fail "worktree add"
(cd ../wt && git nr task1 --from 6.22.7/200001/ORIGINAL >/dev/null && printf 'T = 1\n' >task1.py &&
	git add task1.py && git commit -q -m "feat: task one" && git subir >/dev/null 2>&1 && git switch -q -) ||
	fail "final branch created from a worktree (git nr --from)"
git checkout -q 6.22.7/200001/task1 && git integra -m "feat(task1): add task one" -m "Norms: none" >/dev/null 2>&1 &&
	[ "$(git log -1 --format=%s)" = "feat(task1): add task one" ] && git log -1 --format=%b | grep -q '^Refs: ' &&
	[ "$(git branch --show-current)" = 6.22.7/200001/ORIGINAL ] &&
	ok "agent flow: worktree + git nr --from + git integra -m" || fail "worktree agent flow"
git worktree remove --force ../wt
git checkout -q develop
# a whole structure from stdin: creates what is missing, keeps what exists, adds siblings
printf '6.22.8\n  300001\n    RF1\n      a\n      b\n' | git estructura >/dev/null 2>&1 &&
	git rev-parse -q --verify 6.22.8/300001/RF1/ORIGINAL >/dev/null && git rev-parse -q --verify 6.22.8/300001/RF1/b >/dev/null &&
	[ "$(git branch --show-current)" = develop ] && ok "git estructura creates a tree from stdin" || fail "estructura create"
before="$(git rev-parse 6.22.8/300001/RF1/a)"
out="$(printf '6.22.8/300001/RF1/a\n6.22.8/300001/RF1/c\n' | git es --push 2>&1)" || fail "estructura sibling: $out"
[ "$(git rev-parse 6.22.8/300001/RF1/a)" = "$before" ] && grep -q '= 6.22.8/300001/RF1/a ' <<<"$out" &&
	grep -q '+ 6.22.8/300001/RF1/c ' <<<"$out" && git ls-remote --heads origin | grep -q '6.22.8/300001/RF1/ORIGINAL$' &&
	ok "git estructura keeps existing branches, adds siblings, pushes" || fail "estructura sibling: $out"
if printf '6.22.8/x-1/y\n' | git es >/dev/null 2>&1 || git rev-parse -q --verify 6.22.8/x-1/y >/dev/null; then
	fail "estructura accepted an invalid OT"
else ok "git estructura validates everything before creating"; fi
# release: recursive check, changelog, unmerged branches set aside, tag, merge into develop, tree deleted
git checkout -q develop && printf '# Demo\n\nText.\n' >README.md &&
	printf '<project>\n  <groupId>g</groupId>\n  <artifactId>a</artifactId>\n  <version>6.22.6</version>\n</project>\n' >pom.xml &&
	git add README.md pom.xml && git commit -q -m "build: maven project" && git push -q origin develop 2>/dev/null || fail "pom on develop"
printf '7.1.0\n  300100\n    RF1\n      login\n      pay\n  300101\n    x\n' | git es --push >/dev/null 2>&1 || fail "release tree"
git checkout -q 7.1.0/300100/RF1/login && printf 'L1 = 1\n' >l1.py && git add l1.py && git commit -q -m "feat(login): add form" &&
	git commit -q --allow-empty -m "fix(login): check user" --trailer "Norms: JDA-SEG-010" || fail "release commits"
git checkout -q 7.1.0/300100/RF1/pay && printf 'P1 = 1\n' >p1.py && git add p1.py && git commit -q -m "feat(pay): draft" &&
	git push -q origin HEAD 2>/dev/null || fail "pay branch"
git checkout -q 7.1.0/300100/RF1/login && git integra -m "feat(login): login page" >/dev/null 2>&1 || fail "integra login"
git checkout -q 7.1.0/300100/RF1/ORIGINAL && git integra --force -m "feat(RF1): requirement RF1" >/dev/null 2>&1 || fail "integra RF1"
git checkout -q 7.1.0/300100/ORIGINAL && git integra -m "feat(300100): OT 300100" >/dev/null 2>&1 || fail "integra OT"
git checkout -q develop && printf 'D = 1\n' >d.py && git add d.py && git commit -q -m "fix: hotfix on develop" &&
	git push -q origin develop 2>/dev/null || fail "develop hotfix"
if git changelog v7.1.0 --version 7.1.0 >cl.out 2>&1; then fail "release allowed while develop is ahead"; fi
grep -q "develop has 1 commit(s) that 7.1.0/ORIGINAL lacks" cl.out && ok "release preview: develop must be inside the version ORIGINAL first" ||
	{
		cat cl.out
		fail "develop ahead"
	}
# a plain 'git merge' runs pre-merge-commit before MERGE_HEAD exists: parent into ORIGINAL passes
git checkout -q 7.1.0/ORIGINAL && git merge -q --no-edit develop >subir.out 2>&1 && git push -q origin HEAD 2>/dev/null &&
	ok "plain git merge of the parent into an ORIGINAL passes the hooks" || {
	cat subir.out
	fail "plain merge into ORIGINAL"
}
git checkout -q 7.1.0/300100/RF1/login
if git merge -q --no-edit develop >subir.out 2>&1; then fail "merge into a final branch allowed"; fi
grep -q "breaks the branch model" subir.out && git merge --abort && ok "plain git merge into a final branch is blocked" ||
	{
		cat subir.out
		fail "merge into final"
	}
git checkout -q develop
rm -f subir.out
git branch -q unmerged/7.1.0/300100/RF1/pay develop # a name left by an earlier release
git changelog v7.1.0 --version 7.1.0 -o notes.md >cl.out 2>&1 || {
	cat cl.out
	fail "changelog rc"
}
grep -q '^#### 7.1.0/300100/RF1/login' cl.out && grep -q 'fix(login): check user (.*) \[Norms: JDA-SEG-010\]' cl.out &&
	grep -q '\[ok\] 7.1.0/300101/x: contained in 7.1.0/300101/ORIGINAL' cl.out &&
	grep -q 'pay: 1 commit(s) not in 7.1.0/300100/RF1/ORIGINAL -> will be set aside as unmerged/7.1.0/300100/RF1/pay-2' cl.out &&
	grep -q '^# Release v7.1.0' notes.md && git rev-parse -q --verify 7.1.0/ORIGINAL >/dev/null &&
	ok "git changelog: per-branch changelog, recursive check, free name for the branch set aside" || {
	cat cl.out
	fail "changelog"
}
grep -q '^- Login page (.*; 300100)' cl.out && ok "git changelog: CHANGELOG.md entry in Common Changelog format" ||
	{
		cat cl.out
		fail "release notes preview"
	}
# git release (step 1): the push of RELEASE fails: the tree stays; a second run resumes
mkdir -p "$T/remote.git/hooks"
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile read o n r; do case "$r" in */RELEASE) exit 1 ;; esac; done; exit 0\n' \
	>"$T/remote.git/hooks/pre-receive"
chmod +x "$T/remote.git/hooks/pre-receive"
if git release v7.1.0 --version 7.1.0 --yes >rel.out 2>&1; then fail "release passed a refused push"; fi
grep -q "push of 7.1.0/RELEASE failed" rel.out && git ls-remote --heads origin | grep -q 'refs/heads/7.1.0/ORIGINAL$' &&
	git rev-parse -q --verify 7.1.0/RELEASE >/dev/null && ok "a failed push leaves the branch tree untouched" || {
	cat rel.out
	fail "push failure"
}
rm -f "$T/remote.git/hooks/pre-receive"
git release --version 7.1.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "release resume"
}
subjects="$(git log --format=%s develop..7.1.0/RELEASE | head -n2 | tr '\n' '|')"
[ "$subjects" = "docs(readme): version 7.1.0|docs(changelog): 7.1.0|" ] &&
	[ "$(git branch --show-current)" = 7.1.0/RELEASE ] && [ "$(git show 7.1.0/RELEASE:VERSION)" = 7.1.0 ] &&
	git show 7.1.0/RELEASE:pom.xml | grep -q '<version>7.1.0</version>' &&
	git show 7.1.0/RELEASE:CHANGELOG.md | grep -q '^## 7.1.0 - [0-9-]*$' &&
	git show 7.1.0/RELEASE:CHANGELOG.md | grep -q '^- Login page (' &&
	git show 7.1.0/RELEASE:README.md | grep -q 'qs:version.*version 7.1.0' &&
	[ "$(git for-each-ref --format='%(refname:short)' refs/heads/7.1.0/)" = 7.1.0/RELEASE ] &&
	[ "$(git ls-remote --heads origin | grep -c 'refs/heads/7.1.0/')" = 1 ] &&
	git rev-parse -q --verify unmerged/7.1.0/300100/RF1/pay-2 >/dev/null &&
	git ls-remote --heads origin | grep -q 'refs/heads/unmerged/7.1.0/300100/RF1/pay-2$' &&
	ok "git release: RELEASE with version, CHANGELOG.md and README badge commits; tree deleted; unmerged set aside" ||
	{
		echo "subjects: $subjects"
		cat rel.out
		git log --oneline develop..7.1.0/RELEASE
		fail "release step 1"
	}
git release --version 7.1.0 >rel.out 2>&1 && grep -q 'already prepared' rel.out && ok "git release again: already prepared" || {
	cat rel.out
	fail "release twice"
}
# git publicar (step 2): refused push of develop -> resumes; then merged, tagged, pushed, RELEASE deleted
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/develop ] && exit 1; done; exit 0\n' >"$T/remote.git/hooks/pre-receive"
chmod +x "$T/remote.git/hooks/pre-receive"
if git publicar --yes >rel.out 2>&1; then fail "publicar passed a refused push"; fi
grep -q "push failed" rel.out && git rev-parse -q --verify 7.1.0/RELEASE >/dev/null && ok "git publicar: a failed push keeps RELEASE" ||
	{
		cat rel.out
		fail "publicar push failure"
	}
rm -f "$T/remote.git/hooks/pre-receive"
git publicar --version 7.1.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "publicar resume"
}
[ -z "$(git for-each-ref refs/heads/7.1.0/ refs/remotes/origin/7.1.0/)" ] &&
	git ls-remote --tags origin | grep -q 'refs/tags/v7.1.0$' && git tag -l --format='%(contents)' v7.1.0 | grep -q 'Login page' &&
	[ "$(git log -1 --format=%s develop)" = "chore(release): v7.1.0" ] && git show develop:l1.py >/dev/null &&
	git show develop:CHANGELOG.md | grep -q '^## 7.1.0' && ! git show develop:p1.py >/dev/null 2>&1 &&
	[ "$(git branch --show-current)" = develop ] &&
	ok "git publicar: merged into develop, tag annotated with the notes, RELEASE deleted" || {
	cat rel.out
	fail "publicar"
}
# SemVer: the next version comes from tags, version trees and VERSION
git np patch >np.out 2>&1 && [ "$(git branch --show-current)" = 7.1.1/ORIGINAL ] && [ "$(git show HEAD:VERSION)" = 7.1.1 ] &&
	git show HEAD:pom.xml | grep -q '<version>7.1.1</version>' && [ "$(git log -1 --format=%s)" = "chore(version): 7.1.1" ] &&
	ok "git np patch: next semver, VERSION and pom.xml committed on the ORIGINAL" || {
	cat np.out
	fail "np patch"
}
if git checkout -q develop && git np 7.2 >np.out 2>&1; then fail "non-semver version accepted"; else ok "version root must be semver"; fi
rm -f np.out
# another release reached develop: bringing develop into a tree keeps the tree's version, merges the rest
sed -i 's|<version>7.1.0</version>|<version>7.1.5</version>\n  <description>d</description>|' pom.xml && printf '7.1.5\n' >VERSION &&
	git add pom.xml VERSION && git update-ref HEAD "$(git commit-tree "$(git write-tree)" -p HEAD -m "chore(version): 7.1.5")" || fail "develop 7.1.5"
git checkout -q 7.1.1/ORIGINAL && git merge -q --no-edit develop >m.out 2>&1 && [ "$(cat VERSION)" = 7.1.1 ] &&
	grep -q '<version>7.1.1</version>' pom.xml && grep -q '<description>d</description>' pom.xml &&
	ok "merge driver: VERSION and pom.xml keep the tree version, other pom changes merged" || {
	cat m.out pom.xml VERSION
	fail "merge driver"
}
git checkout -q develop && git reset -q --hard HEAD~1
rm -f m.out
# a version tree copied from a branch of another one (git nueva-version), lives next to it
git checkout -q develop
{ git np 8.0.0 && git np 400001 && git nr a; } >/dev/null 2>&1 && printf 'A = 1\n' >a8.py && git add a8.py &&
	git commit -q -m "feat(a): add a" && git integra -m "feat(a): module a" >/dev/null 2>&1 || fail "tree 8.0.0"
git nr b >/dev/null 2>&1 && printf 'B = 1\n' >b8.py && git add b8.py && git commit -q -m "feat(b): add b" || fail "branch b"
out="$(git nv 8.0.0-SNAPSHOT --from 8.0.0/400001/ORIGINAL 2>&1)" || {
	echo "$out"
	fail "nueva-version"
}
[ "$(git show 8.0.0-SNAPSHOT/ORIGINAL:VERSION)" = 8.0.0-SNAPSHOT ] &&
	git show 8.0.0-SNAPSHOT/ORIGINAL:pom.xml | grep -q '<version>8.0.0-SNAPSHOT</version>' &&
	git show 8.0.0-SNAPSHOT/400001/b:b8.py >/dev/null && git show 8.0.0-SNAPSHOT/400001/ORIGINAL:a8.py >/dev/null &&
	[ "$(git show 8.0.0-SNAPSHOT/400001/b:VERSION)" = 8.0.0-SNAPSHOT ] &&
	git merge-base --is-ancestor 8.0.0-SNAPSHOT/400001/ORIGINAL 8.0.0-SNAPSHOT/400001/b &&
	git merge-base --is-ancestor 8.0.0-SNAPSHOT/ORIGINAL 8.0.0-SNAPSHOT/400001/ORIGINAL &&
	[ "$(git show 8.0.0/ORIGINAL:VERSION)" = 8.0.0 ] && [ "$(git branch --show-current)" = 8.0.0/400001/b ] &&
	ok "git nueva-version: new tree from a branch of another, copies keep their path and work, synced" ||
	{
		echo "$out"
		git arbol 8.0.0-SNAPSHOT
		fail "nueva-version result"
	}
# both trees released; with two RELEASE branches, publicar wants --version; combinar joins them
git integra -m "feat(b): module b" >/dev/null 2>&1 && git integra -m "feat(400001): OT 400001" >/dev/null 2>&1 || fail "integra 8.0.0"
git checkout -q 8.0.0-SNAPSHOT/400001/b && git integra -m "feat(b): module b" >/dev/null 2>&1 &&
	git integra -m "feat(400001): OT 400001" >/dev/null 2>&1 &&
	printf 'S = 1\n' >s8.py && git add s8.py && git commit -q -m "fix(snap): snapshot tweak" || fail "integra snapshot"
git checkout -q develop
git release --version 8.0.0 --yes >rel.out 2>&1 && git release --version 8.0.0-SNAPSHOT --yes >>rel.out 2>&1 ||
	{
		cat rel.out
		fail "release both"
	}
if git publicar --yes >rel.out 2>&1; then fail "publicar picked one of two RELEASE branches"; fi
grep -q 'publish one at a time: git publicar --version' rel.out && ok "two RELEASE branches: publicar needs --version" ||
	{
		cat rel.out
		fail "publicar ambiguity"
	}
git combinar --incluir 8.0.0,8.0.0-SNAPSHOT --version 8.1.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "combinar"
}
cl="$(git show 8.1.0/RELEASE:CHANGELOG.md)"
[ -z "$(git for-each-ref refs/heads/8.0.0/ refs/heads/8.0.0-SNAPSHOT/ refs/remotes/origin/8.0.0/ refs/remotes/origin/8.0.0-SNAPSHOT/)" ] &&
	[ "$(git show 8.1.0/RELEASE:VERSION)" = 8.1.0 ] && git show 8.1.0/RELEASE:pom.xml | grep -q '<version>8.1.0</version>' &&
	git show 8.1.0/RELEASE:a8.py >/dev/null && git show 8.1.0/RELEASE:b8.py >/dev/null && git show 8.1.0/RELEASE:s8.py >/dev/null &&
	[ "$(grep -c '^- Module b' <<<"$cl")" = 1 ] && grep -q '^- Snapshot tweak' <<<"$cl" && grep -q '^## 8.1.0 - ' <<<"$cl" &&
	! grep -q '^## 8.0.0' <<<"$cl" && [ "$(git log --format=%s develop..8.1.0/RELEASE | grep -c '^docs(changelog)')" = 1 ] &&
	git ls-remote --heads origin | grep -q 'refs/heads/8.1.0/RELEASE$' &&
	git rev-parse -q --verify unmerged/8.0.0/RELEASE >/dev/null && git rev-parse -q --verify unmerged/8.0.0-SNAPSHOT/RELEASE >/dev/null &&
	git ls-remote --heads origin | grep -q 'refs/heads/unmerged/8.0.0-SNAPSHOT/RELEASE$' &&
	[ "$(git log --format=%s develop..8.1.0/RELEASE | grep -c '^chore(combine): ')" = 2 ] &&
	ok "git combinar: one squash per tree into 8.1.0/RELEASE, combined ones kept as unmerged/, one changelog entry" ||
	{
		cat rel.out
		echo "$cl"
		git log --oneline --graph develop..8.1.0/RELEASE | head -40
		fail "combinar result"
	}
git publicar --version 8.1.0 --yes >rel.out 2>&1 && [ "$(git log -1 --format=%s develop)" = "chore(release): 8.1.0" ] &&
	ok "git publicar --version: the combined release reaches develop" || {
	cat rel.out
	fail "publicar 8.1.0"
}
rm -f rel.out

# git combinar when develop moved after the trees were prepared: one squash per version on develop
# combine_tree <version> <ot> <source|-> <file> <subject> [<file> <subject>]...: a version tree
# (copied from <source> with git nv, or new from develop) with one integrated final branch per
# file, each writing its subject to it, released as <version>/RELEASE. Exit status: that of git.
combine_tree() {
	local v="$1" ot="$2" from="$3"
	shift 3
	git checkout -q develop
	if [ "$from" = - ]; then git np "$v" >/dev/null 2>&1; else git nv "$v" --from "$from" >/dev/null 2>&1 && git checkout -q "$v/ORIGINAL"; fi
	git np "$ot" >/dev/null 2>&1 || return 1
	while [ "$#" -ge 2 ]; do
		git nr "${1%.py}" >/dev/null 2>&1 && printf 'X = "%s"\n' "$2" >"$1" && git add "$1" && git commit -q -m "$2" &&
			git integra -m "$2" >/dev/null 2>&1 || return 1
		shift 2
	done
	git integra -m "feat($ot): OT $ot" >/dev/null 2>&1 && git checkout -q develop &&
		git release --version "$v" --yes >/dev/null 2>&1
}
# develop_moves <version> <file>: develop gets a change and a published-like CHANGELOG.md entry
# and README.md badge, as git publicar of another release would leave them. Exit status: that of git.
develop_moves() {
	git checkout -q develop && printf 'D = 1\n' >"$2" && git add "$2" && git commit -q -m "fix(${2%.py}): hotfix on develop" &&
		sed -i "0,/^## /s//## $1 - 2026-01-01\n\n### Fixed\n\n- Hotfix on develop\n\n## /" CHANGELOG.md &&
		sed -i -E "s/(qs:version.*version )[0-9][0-9.]*/\1$1/" README.md && git add CHANGELOG.md README.md &&
		git commit -q -m "docs: published $1" && git push -q origin develop 2>/dev/null
}
# combine_checks <target> <A> <B> <file>...: ACs 2-6 of a combination of A and B into the target,
# whose changes are in the files given. Output: ok lines. Exit status: 0, or the test fails.
combine_checks() {
	local c="$1" a="$2" b="$3" f sq cl sqs=()
	shift 3
	sq="$(git log --format=%s "develop..$c/RELEASE" | tac | tr '\n' '|')"
	case "$sq" in "chore(combine): $a changes|chore(combine): $b changes|chore(version): $c|docs(changelog): $c|"*) ;;
	*) fail "combinar $c subjects: $sq" ;; esac
	[ "$(git rev-parse "$(git rev-list --reverse develop.."$c/RELEASE" | sed -n 1p)^")" = "$(git rev-parse develop)" ] &&
		[ -z "$(git rev-list --merges develop.."$c/RELEASE")" ] &&
		ok "git combinar $c: on develop, one squash per RELEASE, then the release commits, no merges" || fail "combinar $c shape"
	mapfile -t sqs < <(git log --format=%H --grep='^chore(combine)' "develop..$c/RELEASE")
	! git diff-tree --no-commit-id --name-only -r "${sqs[@]}" | grep -q '^d' &&
		[ "$(git diff-tree --no-commit-id --name-only -r "${sqs[0]}" | tr '\n' ' ')" = "${*: -1} " ] &&
		ok "git combinar $c: the later squash holds only its own change, nothing of develop" || {
		git show --stat "${sqs[@]}"
		fail "combinar $c squash content"
	}
	cl="$(git show "$c/RELEASE:CHANGELOG.md")"
	[ "$(grep -c "^## $c - " <<<"$cl")" = 1 ] && ! grep -qE "^## ($a|$b) " <<<"$cl" &&
		[ "$(git show develop:CHANGELOG.md | sed -n '/^## /,$p')" = "$(awk -v h="## $c " '/^## /{ skip = index($0, h) == 1 } !skip' <<<"$cl" | sed -n '/^## /,$p')" ] &&
		ok "git combinar $c: one $c entry, develop's entries unchanged" || {
		echo "$cl"
		fail "combinar $c changelog"
	}
	for f in "$@"; do
		[ "$(grep -c "^- .*${f%.py} (.*; [A-Za-z0-9][A-Za-z0-9]*)$" <<<"$cl")" = 1 ] && git show "$c/RELEASE:$f" >/dev/null || {
			echo "$cl"
			fail "combinar $c: $f once in the changelog with its OT, and in the tree"
		}
	done
	[ "$(git show "$c/RELEASE:VERSION")" = "$c" ] && git show "$c/RELEASE:pom.xml" | grep -q "<version>$c</version>" &&
		git show "$c/RELEASE:README.md" | grep -q "qs:version.*version $c" &&
		git log --format=%B --grep='^chore(combine)' develop.."$c/RELEASE" | grep -q "^Squashes: $b/RELEASE [0-9a-f]\{40\}$" &&
		git cat-file -e "$(git log --format=%B --grep='^chore(combine)' develop.."$c/RELEASE" | sed -n "s|^Squashes: $a/RELEASE ||p" | sed -n 1p)" &&
		git log -1 --format=%B "${sqs[0]}" | grep -q '^- .* (OT [0-9]*)$' &&
		git rev-parse -q --verify "unmerged/$a/RELEASE" >/dev/null && git rev-parse -q --verify "unmerged/$b/RELEASE" >/dev/null &&
		git ls-remote --heads origin | grep -q "refs/heads/unmerged/$b/RELEASE$" &&
		[ -z "$(git for-each-ref "refs/heads/$a/" "refs/heads/$b/" "refs/remotes/origin/$a/" "refs/remotes/origin/$b/")" ] &&
		ok "git combinar $c: version, pom and badge, Squashes lines that resolve, originals kept as unmerged/" ||
		fail "combinar $c version files or archive"
}
git checkout -q develop
combine_tree 9.0.0 500001 - a9.py "feat(a9): module a9" g9.py "feat(g9): module g9" || fail "tree 9.0.0"
combine_tree 9.0.1 500002 9.0.0/RELEASE b9.py "fix(b9): fix b9" || fail "tree 9.0.1"
combine_tree 9.0.2 500003 9.0.1/RELEASE e9.py "feat(e9): module e9" || fail "tree 9.0.2"
develop_moves 8.9.9 d9.py || fail "develop moves 8.9.9"
# V1: no merge of develop into the RELEASE branches
git combinar --incluir 9.0.0,9.0.1 --version 9.1.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "combinar 9.1.0"
}
[ "$(grep -c 'WARN: 9.0.[01]/RELEASE lacks .* temporary commit' rel.out)" = 2 ] &&
	grep -q '9.0.0/RELEASE: 5 own commit(s) squashed; dropped 0 mainline merge(s), [1-9] release commit(s), 0 already combined' rel.out &&
	grep -q '9.0.1/RELEASE: 3 own commit(s) squashed; dropped 0 mainline merge(s), [1-9] release commit(s), [1-9][0-9]* already combined' rel.out &&
	ok "git combinar: a warning per RELEASE without develop, counts per RELEASE" || {
	cat rel.out
	fail "combinar 9.1.0 output"
}
combine_checks 9.1.0 9.0.0 9.0.1 a9.py g9.py b9.py
# re-combination: 9.1.0 with 9.0.2, copied from 9.0.1/RELEASE before the first combination
git combinar --incluir 9.1.0,9.0.2 --version 9.2.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "combinar 9.2.0"
}
combine_checks 9.2.0 9.1.0 9.0.2 a9.py g9.py b9.py e9.py
git log -1 --format=%B --grep='^chore(combine): 9.1.0' develop..9.2.0/RELEASE | grep -q '^Squashes: 9.0.0/RELEASE ' &&
	git log -1 --format=%B --grep='^chore(combine): 9.1.0' develop..9.2.0/RELEASE | grep -q '^Squashes: 9.0.1/RELEASE ' &&
	ok "git combinar again: the combined squash carries the Squashes lines of its originals" || fail "combinar 9.2.0 trailers"
git publicar --version 9.2.0 --yes >rel.out 2>&1 && [ "$(git log -1 --format=%s develop)" = "chore(release): 9.2.0" ] &&
	ok "git publicar: a re-combined release reaches develop" || {
	cat rel.out
	fail "publicar 9.2.0"
}
# V2: develop merged by hand into both RELEASE branches first (CHANGELOG.md and badge for develop)
combine_tree 10.0.0 600001 - a10.py "feat(a10): module a10" g10.py "feat(g10): module g10" || fail "tree 10.0.0"
combine_tree 10.0.1 600002 10.0.0/RELEASE b10.py "fix(b10): fix b10" || fail "tree 10.0.1"
develop_moves 9.2.1 d10.py || fail "develop moves 9.2.1"
for v in 10.0.0 10.0.1; do
	git checkout -q "$v/RELEASE"
	if ! git merge -q --no-edit develop >m.out 2>&1; then
		git diff --name-only --diff-filter=U | xargs git checkout --theirs -- && git add -u && git commit -q --no-edit ||
			{
				cat m.out
				fail "merge develop into $v/RELEASE"
			}
	fi
	git push -q origin HEAD 2>/dev/null || fail "push $v/RELEASE"
done
git checkout -q develop
git combinar --incluir 10.0.0,10.0.1 --version 10.1.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "combinar 10.1.0"
}
! grep -q 'WARN: .* lacks' rel.out && grep -q '10.0.1/RELEASE: 3 own commit(s) squashed; dropped 1 mainline merge(s)' rel.out &&
	ok "git combinar after a merge of develop: no warning, the mainline merge dropped" || {
	cat rel.out
	fail "combinar 10.1.0 output"
}
combine_checks 10.1.0 10.0.0 10.0.1 a10.py g10.py b10.py
git publicar --version 10.1.0 --yes >rel.out 2>&1 && [ "$(git log -1 --format=%s develop)" = "chore(release): 10.1.0" ] &&
	ok "git publicar: the combined release reaches develop" || {
	cat rel.out
	fail "publicar 10.1.0"
}
# conflicts: with develop (a file that is not a release file), and between two RELEASE branches
git checkout -q develop && printf 'C = 0\n' >c11.py && git add c11.py && git commit -q -m "feat(c11): add c11" &&
	git push -q origin develop 2>/dev/null || fail "c11 on develop"
combine_tree 11.0.0 700001 - c11.py "feat(c11): change c11" || fail "tree 11.0.0"
combine_tree 11.0.1 700002 - z11.py "feat(z11): add z11" || fail "tree 11.0.1"
combine_tree 11.0.2 700003 - z11.py "feat(z11): other z11" || fail "tree 11.0.2"
git checkout -q develop && printf 'C = 2\n' >c11.py && git commit -q -am "fix(c11): c11 on develop" &&
	git push -q origin develop 2>/dev/null || fail "c11 moves"
refs="$(
	git for-each-ref --format='%(refname) %(objectname)'
	git ls-remote origin
)"
if git combinar --incluir 11.0.0,11.0.1 --version 11.1.0 --yes >rel.out 2>&1; then fail "combinar passed a conflict with develop"; fi
grep -q 'nothing was changed' rel.out && grep -q '^    c11.py$' rel.out && grep -q 'git checkout 11.0.0/RELEASE && git merge develop' rel.out &&
	[ "$(
		git for-each-ref --format='%(refname) %(objectname)'
		git ls-remote origin
	)" = "$refs" ] &&
	[ "$(git worktree list | wc -l)" = 1 ] && [ ! -e .git/quality-suite/combine-wt ] &&
	ok "git combinar: a conflict with develop changes nothing and prints the steps" || {
	cat rel.out
	fail "combinar conflict with develop"
}
if git combinar --incluir 11.0.1,11.0.2 --version 11.1.0 --yes >rel.out 2>&1; then fail "combinar passed a conflict between trees"; fi
grep -q 'nothing was changed' rel.out && grep -q '^    z11.py$' rel.out &&
	[ "$(
		git for-each-ref --format='%(refname) %(objectname)'
		git ls-remote origin
	)" = "$refs" ] &&
	[ "$(git worktree list | wc -l)" = 1 ] && [ ! -e .git/quality-suite/combine-wt ] &&
	ok "git combinar: a conflict between RELEASE branches changes nothing" || {
	cat rel.out
	fail "combinar conflict between trees"
}
git push -q origin --delete 11.0.0/RELEASE 11.0.1/RELEASE 11.0.2/RELEASE 2>/dev/null &&
	git branch -q -D 11.0.0/RELEASE 11.0.1/RELEASE 11.0.2/RELEASE || fail "clean 11.x"
rm -f rel.out m.out

# all or nothing, the origin renames in the plan, the order by author date
# dated_tree <author date> <committer date> <combine_tree arguments>...: combine_tree with fixed
# dates, as a rebase or a cherry-pick leaves them (new committer date, same author date).
# Exit status: that of combine_tree.
dated_tree() {
	(
		export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$2"
		shift 2
		combine_tree "$@"
	)
}
# all_refs: every local ref, origin's refs and HEAD, to compare before and after. Output: lines.
all_refs() {
	git for-each-ref --format='%(refname) %(objectname)'
	git ls-remote origin
	git symbolic-ref -q HEAD || git rev-parse HEAD
}
# why: the committer dates say the newer tree is older; the author dates of the version commits do not
dated_tree "2030-01-01T10:00:00Z" "2030-05-01T10:00:00Z" 12.0.0 800001 - a12.py "feat(a12): module a12" || fail "tree 12.0.0"
dated_tree "2030-02-01T10:00:00Z" "2030-04-01T10:00:00Z" 12.0.1 800002 - b12.py "feat(b12): module b12" || fail "tree 12.0.1"
dated_tree "2030-01-15T10:00:00Z" "2030-01-15T10:00:00Z" 12.0.2 800003 - e12.py "feat(e12): module e12" || fail "tree 12.0.2"
refs="$(all_refs)"
if command -v script >/dev/null 2>&1; then
	printf 'n\n' | script -qec "git combinar --incluir 12.0.0,12.0.1 --version 12.1.0" /dev/null >rel.out 2>&1 || true
	grep -q 'origin: 12.0.0/RELEASE -> unmerged/12.0.0/RELEASE  (renamed on origin' rel.out &&
		grep -q 'origin: 12.0.1/RELEASE -> unmerged/12.0.1/RELEASE' rel.out && grep -q 'cancelled; nothing was changed' rel.out &&
		[ "$(all_refs)" = "$refs" ] && ok "git combinar: the plan names the origin renames and asks first; a no changes nothing" || {
		cat rel.out
		fail "combinar plan of the origin renames"
	}
fi
mkdir -p "$T/reject-hooks" && printf '#!/bin/sh\necho "rejected by the test" >&2\nexit 1\n' >"$T/reject-hooks/pre-commit" &&
	chmod +x "$T/reject-hooks/pre-commit"
# why: the rejecting hook is what the test checks (combinar must survive a failing commit hook)
if git -c core.hooksPath="$T/reject-hooks" combinar --incluir 12.0.0,12.0.1 --version 12.1.0 --yes >rel.out 2>&1; then
	fail "combinar passed a rejected release commit"
fi
grep -q 'origin: 12.0.0/RELEASE -> unmerged/12.0.0/RELEASE' rel.out && grep -q 'rejected .*nothing was changed' rel.out &&
	[ "$(all_refs)" = "$refs" ] && [ "$(git worktree list | wc -l)" = 1 ] && [ ! -e .git/quality-suite/combine-wt ] &&
	! git config qs.release.12.1.0.tag >/dev/null && git diff --quiet && git diff --cached --quiet && ok "git combinar: a rejected release commit leaves branches, HEAD and origin unchanged" || {
	cat rel.out
	diff <(echo "$refs") <(all_refs) || true
	fail "combinar failure injection"
}
# origin rejects the push: the local result stays, origin is unchanged, the push to run is printed
mkdir -p "$T/remote-hooks" && printf '#!/bin/sh\nexit 1\n' >"$T/remote-hooks/pre-receive" && chmod +x "$T/remote-hooks/pre-receive" &&
	git -C "$T/remote.git" config core.hooksPath "$T/remote-hooks" || fail "remote hook"
remote="$(git ls-remote origin)"
if GIT_COMMITTER_DATE="2030-06-01T10:00:00Z" git combinar --incluir 12.0.0,12.0.1 --version 12.1.0 --yes >rel.out 2>&1; then
	fail "combinar passed a rejected push"
fi
push="$(sed -n 's/^  \(git push --atomic .*\)$/\1/p' rel.out)"
[ -n "$push" ] && [ "$(git ls-remote origin)" = "$remote" ] && [ "$(git branch --show-current)" = 12.1.0/RELEASE ] &&
	git rev-parse -q --verify refs/heads/unmerged/12.0.0/RELEASE >/dev/null && ! git rev-parse -q --verify refs/heads/12.0.0/RELEASE >/dev/null &&
	git -C "$T/remote.git" config --unset core.hooksPath && bash -c "$push" >/dev/null 2>&1 &&
	git ls-remote --heads origin | grep -q 'refs/heads/12.1.0/RELEASE$' &&
	git ls-remote --heads origin | grep -q 'refs/heads/unmerged/12.0.1/RELEASE$' &&
	! git ls-remote --heads origin | grep -qE 'refs/heads/12.0.[01]/RELEASE$' &&
	ok "git combinar: a rejected push keeps the local result, origin unchanged, and prints the atomic push" || {
	cat rel.out
	fail "combinar push failure"
}
[ "$(git log --format=%s develop..12.1.0/RELEASE | tac | sed -n 1,2p | tr '\n' '|')" = "chore(combine): 12.0.0 changes|chore(combine): 12.0.1 changes|" ] &&
	[ "$(git log -1 --format=%at --grep='^chore(combine): 12.0.0' develop..12.1.0/RELEASE)" = "$(date -d 2030-01-01T10:00:00Z +%s)" ] &&
	ok "git combinar: trees ordered by the author date of their version commit; the squash keeps it" || {
	git log --format='%s %ad %cd' develop..12.1.0/RELEASE
	fail "combinar order by author date"
}
# the originals gone: the squash dates still put the combined RELEASE before a later tree
git checkout -q develop && git push -q origin --delete unmerged/12.0.0/RELEASE unmerged/12.0.1/RELEASE &&
	git branch -q -D unmerged/12.0.0/RELEASE unmerged/12.0.1/RELEASE && rm -rf .git/logs && git gc -q --prune=now || fail "drop 12.0.x"
! git cat-file -e "$(sed -n 's|^refs/heads/12.0.0/RELEASE ||p' <<<"$refs")" 2>/dev/null || fail "12.0.0/RELEASE still in the object store"
git combinar --incluir 12.1.0,12.0.2 --version 12.2.0 --yes >rel.out 2>&1 || {
	cat rel.out
	fail "combinar 12.2.0"
}
grep -q 'WARN: 12.0.0/RELEASE .* is gone' rel.out &&
	[ "$(git log --format=%s --grep='^chore(combine)' develop..12.2.0/RELEASE | tac | tr '\n' '|')" = "chore(combine): 12.1.0 changes|chore(combine): 12.0.2 changes|" ] &&
	ok "git combinar: a combined RELEASE whose originals are gone keeps its place by the squash dates" || {
	cat rel.out
	git log --format='%s %ad %cd' develop..12.2.0/RELEASE
	fail "combinar order without originals"
}
git checkout -q develop && git push -q origin --delete 12.2.0/RELEASE unmerged/12.1.0/RELEASE unmerged/12.0.2/RELEASE &&
	git branch -q -D 12.2.0/RELEASE unmerged/12.1.0/RELEASE unmerged/12.0.2/RELEASE &&
	git config --unset qs.release.12.2.0.tag || fail "clean 12.x"
rm -f rel.out

# the rollback cannot put a branch back (it moved meanwhile): HEAD must not be left on a missing branch
dated_tree "2031-01-01T10:00:00Z" "2031-01-01T10:00:00Z" 13.0.0 810001 - a13.py "feat(a13): module a13" || fail "tree 13.0.0"
dated_tree "2031-02-01T10:00:00Z" "2031-02-01T10:00:00Z" 13.0.1 810002 - b13.py "feat(b13): module b13" || fail "tree 13.0.1"
git checkout -q 13.0.0/RELEASE || fail "checkout 13.0.0/RELEASE"
mkdir -p "$T/move-hooks" && cat >"$T/move-hooks/post-checkout" <<'EOF'
#!/bin/sh
# once the new release is checked out: move an archived branch, then fail
if [ "$(git symbolic-ref -q HEAD)" = refs/heads/13.1.0/RELEASE ]; then
	git update-ref refs/heads/unmerged/13.0.0/RELEASE "$(git rev-parse develop)"
	exit 1
fi
EOF
chmod +x "$T/move-hooks/post-checkout"
# why: the failing post-checkout hook is what the test checks
git -c core.hooksPath="$T/move-hooks" combinar --incluir 13.0.0,13.0.1 --version 13.1.0 --yes >rel.out 2>&1 && fail "combinar passed a failing post-checkout"
{ ! git symbolic-ref -q HEAD >/dev/null || git rev-parse -q --verify "$(git symbolic-ref -q HEAD)" >/dev/null; } &&
	git rev-parse -q --verify HEAD >/dev/null && grep -q 'WARN: HEAD was left detached' rel.out &&
	ok "git combinar: a rollback that is rejected leaves HEAD detached, never on a missing branch" || {
	cat rel.out
	git status | head -3
	fail "combinar dangling HEAD"
}

tree="$(git arbol)"
grep -q '^~  unmerged/7.1.0/300100/RF1/pay-2' <<<"$tree" && ok "git arbol shows branches set aside" || fail "arbol archived: $tree"
git branch -q -D unmerged/7.1.0/300100/RF1/pay
rm -f cl.out rel.out notes.md
unset GIT_EDITOR

# standard repository files: created at install from the history and pom.xml, checked by the gate
git init -q -b develop "$T/repo-files"
cd "$T/repo-files"
git config user.email ana@example.org
git config user.name "Ana Example"
printf '<project>\n  <groupId>es.x</groupId>\n  <artifactId>demo</artifactId>\n  <version>1.1.0-SNAPSHOT</version>\n  <name>Demo App</name>\n  <description>Demo application.</description>\n</project>\n' >pom.xml
git add pom.xml && git commit -q -m "feat: first version" && git tag v1.0.0
QS_REPO_FILES=1 "$SUITE/install.sh" "$T/repo-files" >inst.out 2>&1 || {
	cat inst.out
	fail "install with repository files"
}
missing=""
for f in README.md CHANGELOG.md VERSION CONTRIBUTING.md CODE_OF_CONDUCT.md LICENSE AUTHORS CONTRIBUTORS.md \
	CITATION.cff SECURITY.md SUPPORT.md CODEOWNERS MAINTAINERS.md ROADMAP.md FAQ.md INSTALL.md ARCHITECTURE.md API.md DEVELOPMENT.md; do
	[ -f "$f" ] || missing="$missing $f"
done
[ -z "$missing" ] && [ "$(cat VERSION)" = 1.1.0 ] && grep -q '^## \[\{0,1\}1.0.0\]\{0,1\} - ' CHANGELOG.md &&
	grep -q '^# Demo App' README.md && grep -q 'version 1.0.0' README.md && grep -q 'Ana Example <ana@example.org>' AUTHORS &&
	ok "install creates the 19 standard files from git history and pom.xml" || {
	cat inst.out
	echo "missing:$missing"
	fail "repository files"
}
rm -f inst.out
printf 'own text\n' >FAQ.md
out="$(git repo-files 2>&1)" && grep -q 'FAQ.md *exists' <<<"$out" && [ "$(cat FAQ.md)" = "own text" ] &&
	git repo-files --force FAQ.md >/dev/null 2>&1 && grep -q '^# FAQ' FAQ.md &&
	ok "git repo-files never overwrites; --force NAME regenerates one" || {
	echo "$out"
	fail "repo-files again"
}
git add -A && out="$(git commit -m "docs: repository files" 2>&1)" && grep -q 'qs:fill' <<<"$out" &&
	ok "generated files commit (placeholders only warn)" || {
	echo "$out"
	fail "commit repository files"
}
printf '1.0\n' >VERSION && git add VERSION
if git commit -q -m "chore: bad version" 2>/dev/null; then fail "non-semver VERSION committed"; else ok "gate: VERSION must be semver"; fi
git checkout -q HEAD -- VERSION
printf '\n## [Unreleased]\n' >>CHANGELOG.md && git add CHANGELOG.md
if out="$(git commit -m "docs: unreleased" 2>&1)"; then fail "invalid CHANGELOG.md committed"; fi
grep -q "Unreleased" <<<"$out" && ok "gate: CHANGELOG.md follows Common Changelog" || {
	echo "$out"
	fail "changelog gate"
}
git checkout -q HEAD -- CHANGELOG.md
cd "$T/repo"

# agents: the Claude Code hook gets the gate findings for the file it just edited
printf 'def broken(:\n  pass\n' >agent.py
rc=0
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/agent.py"}}' "$PWD" |
	"$SUITE/scripts/qs-run.sh" --hook 2>agent.err || rc=$?
[ "$rc" = 2 ] && grep -q "Quality gate findings" agent.err && ok "agent hook reports findings (exit 2)" ||
	fail "agent hook rc=$rc: $(cat agent.err)"
printf 'x = 1\n' >agent.py
rc=0
printf '{"tool_input":{"file_path":"agent.py"}}' | "$SUITE/scripts/qs-run.sh" --hook 2>/dev/null || rc=$?
[ "$rc" = 0 ] && ok "agent hook quiet on clean files" || fail "agent hook on clean file rc=$rc"
# the hook resolves the repository from the edited file (agents in a worktree), not from its cwd
mkdir -p sub
printf 'def broken(:\n  pass\n' >sub/agent2.py
rc=0
(
	cd /
	printf '{"tool_input":{"file_path":"%s/sub/agent2.py"}}' "$OLDPWD" | "$SUITE/scripts/qs-run.sh" --hook
) 2>agent.err || rc=$?
[ "$rc" = 2 ] && grep -q "sub/agent2.py" agent.err && ok "agent hook finds the repository from the file path" ||
	fail "agent hook from another cwd rc=$rc: $(cat agent.err)"
rm -rf agent.py agent.err sub

# one image per suite version for every repository: a second repo reuses the tools of the first
# shellcheck disable=SC2016
[ "$(readlink .git/hooks/pre-commit)" = "$QS_HOME/hooks/pre-commit" ] && grep -q 'exec bash "$SUITE/hooks/pre-commit"' "$QS_HOME/hooks/pre-commit" &&
	! grep -q '^QUALITY_SUITE_IMAGE=' .git/hooks/quality-suite.env &&
	ok "repo hooks are symbolic links to one common folder; the image is not frozen per repository" || fail "common hooks / image key"
git init -q -b main "$T/repo2"
(cd "$T/repo2" && git config user.email t@example.com && git config user.name tester &&
	QS_HOOK_LINKS=0 "$SUITE/install.sh" "$T/repo2" >/dev/null && printf 'x = 1\n' >a.py && printf 'int main(void) { return 0; }\n' >m.c &&
	git add a.py m.c && git commit -q -m "feat: python and c") >/dev/null 2>&1 || fail "commit in a second repository"
last="$(grep '^LAYER' "$FAKE_DOCKER_DIR/calls.log" | tail -n1)"
grep -qw c <<<"${last##*:}" && ! grep -qw python <<<"${last##*:}" && grep -q "code-quality-suite:$(cat "$SUITE/VERSION")" <<<"$last" &&
	ok "second repository adds only its new languages to the shared image" || fail "shared image: $last"
grep -qxF "$T/repo2" "$QS_HOME/repos.list" && ok "installed repositories are registered" || fail "repos.list"
[ ! -L "$T/repo2/.git/hooks/pre-commit" ] && grep -q "exec \"$QS_HOME/hooks/pre-commit\"" "$T/repo2/.git/hooks/pre-commit" &&
	ok "without symbolic links a one-line stub runs the common hook (commits above went through it)" || fail "stub hook"
# a lock left by a killed commit (dead pid) does not block the next one
mkdir -p "$QS_HOME/image.lock"
echo 999999 >"$QS_HOME/image.lock/pid"
date +%s >"$QS_HOME/image.lock/since"
(cd "$T/repo2" && printf 'local x = 1\nreturn x\n' >m.lua && git add m.lua && timeout 120 git commit -q -m "feat: lua") >/dev/null 2>&1 &&
	[ ! -d "$QS_HOME/image.lock" ] && ok "stale install lock is taken over and released" || fail "stale lock"
# a tools layer that fails to build keeps the image, says so, and the commit still runs the checks
(cd "$T/repo2" && printf '[main]\nkey = value\n' >s.ini && git add s.ini && FAKE_DOCKER_FAIL_BUILD=1 git commit -q -m "feat: ini") 2>fail.err &&
	grep -q "could not be added to the image" fail.err && grep -q "installer crashed: simulated" fail.err &&
	! docker image inspect -f '{{index .Config.Labels "qs.langs"}}' "code-quality-suite:$(cat "$SUITE/VERSION")" | grep -qw ini &&
	ok "a failed tools layer is reported (log tail) and the commit still runs the built-in checks" ||
	{
		cat fail.err >&2
		fail "failed layer"
	}
rm -f fail.err
# suite moved: the wrapper blocks with a clear message instead of skipping the checks
sed -i.bak 's|^QUALITY_SUITE_DIR=.*|QUALITY_SUITE_DIR="/nonexistent"|' "$T/repo2/.git/hooks/quality-suite.env"
(cd "$T/repo2" && printf 'y = 2\n' >b.py && git add b.py && git commit -q -m "feat: b") 2>moved.err &&
	fail "commit passed without the suite" || { grep -q "the suite is not at '/nonexistent'" moved.err &&
		ok "missing suite blocks the commit with instructions" || fail "moved suite: $(cat moved.err)"; }
# update: a new suite version in another folder -> images removed, repositories re-pointed,
# tools reinstalled on the next commit like a clean install
cp -r "$SUITE" "$T/suite2"
echo 9.9.9 >"$T/suite2/VERSION"
"$T/suite2/scripts/qs-update.sh" --yes --lazy >update.log 2>&1 || fail "qs-update: $(cat update.log)"
# shellcheck disable=SC2143,SC2010
grep -q "re-pointed $(grep -c . "$QS_HOME/repos.list") repositories" update.log && [ -z "$(ls "$FAKE_DOCKER_DIR" | grep -F '@')" ] &&
	grep -q "QUALITY_SUITE_DIR=\"$T/suite2\"" "$T/repo2/.git/hooks/quality-suite.env" &&
	ok "git actualizar-suite: images removed, repositories re-pointed" || fail "update: $(
	cat update.log
	ls "$FAKE_DOCKER_DIR"
)"
(cd "$T/repo2" && git commit -q -m "feat: b") >/dev/null 2>&1 || fail "commit after the update"
last="$(grep '^LAYER' "$FAKE_DOCKER_DIR/calls.log" | tail -n1)"
grep -q 'code-quality-suite:9.9.9' <<<"$last" && grep -qw python <<<"${last##*:}" &&
	ok "after the update the first commit reinstalls its tools in the new image" || fail "reinstall: $last"
"$T/suite2/scripts/qs-update.sh" --status >status.log 2>&1
grep -q "Tools for    : _global python" status.log &&
	ok "qs-update --status" || fail "status: $(cat status.log)"
rm -f moved.err update.log
# cleanup of the images and containers of old suite versions (qs_clean_old_images). Own QS_HOME
# and repositories; the fake docker keeps the images as JSON files and the containers in
# containers.json. "Calls" are the lines of calls.log.
QS_HOME_MAIN="$QS_HOME"
export QS_HOME="$T/qs-clean-home"
CUR="$(cat "$SUITE/VERSION")"
CALLS="$FAKE_DOCKER_DIR/calls.log"
CL="$T/clean"
mkdir -p "$CL"
LABELLED='{"labels": {"org.opencontainers.image.title": "code-quality-suite"}}'

# Create a fake image. Arguments: <tag> <json of the image>. Returns 0.
fx_image() {
	local n="${1//\//_}"
	n="${n//:/@}"
	printf '%s' "$2" >"$FAKE_DOCKER_DIR/$n.json"
}
# Does the fake image exist? Arguments: <tag>. Returns 0 if it does, 1 if it does not.
img_exists() {
	local n="${1//\//_}"
	n="${n//:/@}"
	[ -f "$FAKE_DOCKER_DIR/$n.json" ]
}
# Reset the fake Docker to the fixture of the spec: the suite images of old and newer versions,
# a non-version tag and two foreign images, no containers, an empty call log. Returns 0.
fx_reset() {
	local t
	rm -rf "$FAKE_DOCKER_DIR"
	mkdir -p "$FAKE_DOCKER_DIR"
	for t in 2.6.0 3.0.0 4.0.2 wt-textot base-2.6.0 base-3.0.0 base-4.0.2 9.9.9; do
		fx_image "code-quality-suite:$t" "$LABELLED"
	done
	for t in code-quality-suite-foo:1.0.0 my/code-quality-suite:1.0.0 host/code-quality-suite:1.0.0; do
		fx_image "$t" "$LABELLED"
	done
	fx_image python:3.12-slim '{"labels": {}}'
	fx_image zricethezav/gitleaks:latest '{"labels": {}}'
	: >"$CALLS"
}
# Write the fake containers. Arguments: <json list of {id, image, state}>. Returns 0.
fx_containers() { printf '%s' "$1" >"$FAKE_DOCKER_DIR/containers.json"; }
# Is there a call matching an extended regular expression? Arguments: <regex>. Returns 0 if so.
calls_match() { grep -qE -- "$1" "$CALLS"; }
# Does the output file contain a fixed string? Arguments: <string> [file]. Returns 0 if so.
out_has() { grep -qF -- "$1" "${2:-$CL/out}"; }
# Install the suite into a repository, output in $CL/out. Arguments: <repo>. Returns the exit status.
inst() { "$SUITE/install.sh" "$1" >"$CL/out" 2>&1; }
# Run a cleanup check: description, then a condition (a command). Exits the test on failure.
check() {
	local d="$1"
	shift
	if "$@"; then ok "$d"; else
		echo "--- output:" >&2
		cat "$CL/out" >&2 2>/dev/null || true
		echo "--- calls:" >&2
		cat "$CALLS" >&2
		fail "$d"
	fi
}
# AC1-3, 4, 6, 7: install removes the older versions, their stopped containers, nothing else
ac_install() {
	local t
	for t in 2.6.0 3.0.0 4.0.2 base-2.6.0 base-3.0.0 base-4.0.2; do
		calls_match "^image rm code-quality-suite:$t\$" && ! img_exists "code-quality-suite:$t" || return 1
	done
	img_exists "code-quality-suite:$CUR" && img_exists "code-quality-suite:base-$CUR"
}
# No call names the foreign images and both still exist. Returns 0 when so.
ac_foreign_safe() {
	! calls_match 'python:3.12-slim|zricethezav/gitleaks' && img_exists python:3.12-slim && img_exists zricethezav/gitleaks:latest
}
# No look-alike repository (code-quality-suite-foo, my/..., host/...) was removed. Returns 0 when so.
ac_lookalikes_safe() {
	! calls_match '^image rm .*(code-quality-suite-foo|my/|host/)' &&
		img_exists code-quality-suite-foo:1.0.0 && img_exists my/code-quality-suite:1.0.0 && img_exists host/code-quality-suite:1.0.0
}
# No cleanup removal passes -f. Returns 0 when none does.
ac_no_force() { ! calls_match '^(image )?rm .*-f'; }

git init -q -b main "$CL/r1"
fx_reset
fx_containers '[{"id":"c2","image":"code-quality-suite:3.0.0","state":"exited"},{"id":"c3","image":"code-quality-suite:'"$CUR"'","state":"created"}]'
inst "$CL/r1" || fail "install for the cleanup checks: $(cat "$CL/out")"
check "AC1 install removes the older versions and their bases" ac_install
check "AC2 foreign images are never touched" ac_foreign_safe
check "AC2 look-alike repositories never get an image rm" ac_lookalikes_safe
check "AC3 a non-version tag is kept with a note" out_has "kept code-quality-suite:wt-textot (not a version tag"
check "AC3 wt-textot is still there" img_exists code-quality-suite:wt-textot
check "AC4 a newer version is kept on install, with a note" out_has "newer than $CUR"
check "AC4 9.9.9 still there" img_exists code-quality-suite:9.9.9
check "AC6 stopped containers go, current version included, without -f" bash -c "grep -qx 'rm c2' '$CALLS' && grep -qx 'rm c3' '$CALLS'"
check "AC6 no -f in rm / image rm" ac_no_force
check "AC7 prune only with the suite label" bash -c "grep -qx 'image prune -f --filter label=org.opencontainers.image.title=code-quality-suite' '$CALLS' && ! grep '^image prune' '$CALLS' | grep -vq 'label=org.opencontainers.image.title=code-quality-suite'"
check "AC1 summary line" out_has "removed 6 old image(s) and 2 stopped container(s)"
# AC8: a second install has nothing left to remove
: >"$CALLS"
inst "$CL/r1" || fail "second install"
check "AC8 second install is idempotent: no rm, no image rm, no summary" bash -c "! grep -qE '^(rm|image rm)( |\$)' '$CALLS' && ! grep -q 'removed ' '$CL/out'"

# AC5: a running container keeps its image; its base is untagged; the rest goes
ac_running() {
	! calls_match '^(rm|stop|kill)( .*)? c1( |$)' && ! calls_match '^image rm code-quality-suite:4.0.2$' &&
		calls_match '^image rm code-quality-suite:base-4.0.2$' && calls_match '^image rm code-quality-suite:2.6.0$' &&
		img_exists code-quality-suite:4.0.2 && grep -q '"c1"' "$FAKE_DOCKER_DIR/containers.json"
}
fx_reset
fx_containers '[{"id":"c1","image":"code-quality-suite:4.0.2","state":"running"}]'
inst "$CL/r1" || fail "install with a running container"
check "AC5 install: the running container is not touched, its image is kept with a warning" ac_running
check "AC5 install: warning text" out_has "WARN: kept code-quality-suite:4.0.2: container c1 is running"
fx_reset
fx_containers '[{"id":"c1","image":"code-quality-suite:4.0.2","state":"running"}]'
"$SUITE/scripts/qs-update.sh" --yes --lazy >"$CL/out" 2>&1 || fail "update with a running container: $(cat "$CL/out")"
check "AC5 update: the running container survives (it used to be killed)" ac_running
check "AC5 update: warning text" out_has "WARN: kept code-quality-suite:4.0.2: container c1 is running"
check "AC4 update removes the newer version" bash -c "! test -f '$FAKE_DOCKER_DIR/code-quality-suite@9.9.9.json'"
check "AC3 update keeps wt-textot, with the note" out_has "kept code-quality-suite:wt-textot (not a version tag"
check "AC3 wt-textot survives the update" img_exists code-quality-suite:wt-textot
check "AC2 update does not touch foreign images" ac_foreign_safe
check "AC6 update never uses -f" ac_no_force

# AC9: the opt-outs
fx_reset
QS_KEEP_OLD_IMAGES=1 inst "$CL/r1" || fail "install with QS_KEEP_OLD_IMAGES"
check "AC9 QS_KEEP_OLD_IMAGES=1: nothing removed" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"
check "AC9 QS_KEEP_OLD_IMAGES=1: says so" out_has "old images kept"
fx_reset
"$SUITE/scripts/qs-update.sh" --yes --lazy --keep-old >"$CL/out" 2>&1 || fail "update --keep-old"
check "AC9 --keep-old: nothing removed" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"
check "AC9 --keep-old: says so" out_has "old images kept"
check "AC2 foreign images after AC9" ac_foreign_safe

# AC10: no docker, or Docker down: silent, and the hooks are still installed
mkdir -p "$CL/nodocker"
for c in tr uname; do ln -sf "$(command -v "$c")" "$CL/nodocker/$c"; done
# shellcheck disable=SC2016 # why: the quoted script is expanded by the inner bash, not here
out="$(PATH="$CL/nodocker" QUALITY_SUITE_DIR="$SUITE" "$BASH" -c '. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"; qs_clean_old_images; echo "rc=$?"' 2>&1)"
check "AC10 without docker on PATH: prints nothing and returns 0" test "$out" = "rc=0"
fx_reset
out="$(FAKE_DOCKER_DOWN=1 QUALITY_SUITE_DIR="$SUITE" bash -c '. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"; qs_clean_old_images; echo "rc=$?"' 2>&1)"
check "AC10 Docker down: prints nothing and returns 0" test "$out" = "rc=0"
git init -q -b main "$CL/r5"
FAKE_DOCKER_DOWN=1 inst "$CL/r5" || fail "install with Docker down"
check "AC10 Docker down: the hooks are still installed" test -x "$CL/r5/.git/hooks/pre-commit"

# AC11: a hook that builds a new version lazily removes nothing
echo 4.3.0 >"$T/suite2/VERSION"
git init -q -b main "$CL/r3"
QS_SKIP_IMAGE=1 "$T/suite2/install.sh" "$CL/r3" >/dev/null 2>&1 || fail "hooks of suite2 into r3"
fx_reset
(cd "$CL/r3" && git config user.email t@example.com && git config user.name tester && printf 'x = 1\n' >a.py &&
	git add a.py && git commit -q -m "feat: a") >"$CL/out" 2>&1 || fail "commit that builds a new version lazily: $(cat "$CL/out")"
check "AC11 a lazy build by a hook removes nothing" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"
check "AC11 and prints the note about the other versions" out_has "Images of other suite versions are still on disk"
check "AC11 the new version is built" img_exists code-quality-suite:4.3.0

# AC12: a custom target builds and cleans nothing
fx_reset
bash "$SUITE/scripts/build-image.sh" "$SUITE" code-quality-suite:dev >"$CL/out" 2>&1 || fail "build-image dev"
check "AC12 build-image with a custom tag makes no cleanup calls" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"

# AC13: a version another registered repository uses is kept on install, removed by the update
echo 4.0.2 >"$T/suite2/VERSION"
QS_SKIP_IMAGE=1 "$T/suite2/install.sh" "$CL/r3" >/dev/null 2>&1 || fail "hooks of suite2 (4.0.2) into r3"
fx_reset
inst "$CL/r1" || fail "install with a used version"
check "AC13 install keeps a version used by another repository (and its base)" bash -c "
	grep -q 'used by .*r3' '$CL/out' && test -f '$FAKE_DOCKER_DIR/code-quality-suite@4.0.2.json' &&
	test -f '$FAKE_DOCKER_DIR/code-quality-suite@base-4.0.2.json'"
check "AC13 the used version is reported with its repository and the fix" out_has "git actualizar-suite moves every repository to $CUR"
"$SUITE/scripts/qs-update.sh" --yes --lazy >"$CL/out" 2>&1 || fail "update with a used version: $(cat "$CL/out")"
check "AC13 update removes it and re-points the repository" bash -c "
	! test -f '$FAKE_DOCKER_DIR/code-quality-suite@4.0.2.json' && ! test -f '$FAKE_DOCKER_DIR/code-quality-suite@base-4.0.2.json' &&
	grep -q 'QUALITY_SUITE_DIR=\"$SUITE\"' '$CL/r3/.git/hooks/quality-suite.env'"

# AC14: a version that is not semver: no cleanup, one note
echo latest >"$T/suite2/VERSION"
git init -q -b main "$CL/r4"
fx_reset
"$T/suite2/install.sh" "$CL/r4" >"$CL/out" 2>&1 || fail "install of a non-semver suite"
check "AC14 non-semver version: no cleanup calls" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"
check "AC14 non-semver version: exactly one note" test "$(grep -c 'not a release version' "$CL/out")" = 1

# AC15: --status shows the plan and changes nothing
fx_reset
"$SUITE/scripts/qs-update.sh" --status >"$CL/out" 2>&1 || fail "status"
check "AC15 --status lists what would be removed" out_has "would remove: code-quality-suite:4.0.2"
check "AC15 --status lists what is kept" out_has "kept: code-quality-suite:wt-textot (not a version tag"
check "AC15 --status changes nothing" bash -c "! grep -qE '^(rm|image rm|image prune)( |\$)' '$CALLS'"

# AC16: version helpers
cmp_check() {
	local out rc=0
	out="$(QUALITY_SUITE_DIR="$SUITE" bash -c '. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"; qs_semver_cmp "$@"' _ "$1" "$2")" || rc=$?
	[ "$out" = "$3" ] && [ "$rc" = "${4:-0}" ]
}
tag_check() {
	local out rc=0
	out="$(QUALITY_SUITE_DIR="$SUITE" bash -c '. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"; qs_tag_version "$1"' _ "$1")" || rc=$?
	[ "$out" = "$2" ] && [ "$rc" = "$3" ]
}
check "AC16 4.0.10 > 4.0.9" cmp_check 4.0.10 4.0.9 1
check "AC16 4.2.0 > 4.2.0-rc1" cmp_check 4.2.0 4.2.0-rc1 1
check "AC16 3.0.0 < 4.0.0" cmp_check 3.0.0 4.0.0 -1
check "AC16 4.2.0 = 4.2.0" cmp_check 4.2.0 4.2.0 0
check "AC16 4.2.0-rc2 > 4.2.0-rc1" cmp_check 4.2.0-rc2 4.2.0-rc1 1
check "AC16 4.1.0 > 4.1.0-rc.1" cmp_check 4.1.0 4.1.0-rc.1 1
check "AC16 4.1.0-SNAPSHOT < 4.1.0" cmp_check 4.1.0-SNAPSHOT 4.1.0 -1
check "AC16 4.1.0-SNAPSHOT > 4.0.9" cmp_check 4.1.0-SNAPSHOT 4.0.9 1
check "AC16 wt-textot is not semver" cmp_check wt-textot 4.2.0 "" 2
check "AC16 base-4.0.2 gives 4.0.2" tag_check base-4.0.2 4.0.2 0
check "AC16 wt-textot is not a version tag" tag_check wt-textot "" 1

# AC17: one removal fails: warning with the tag, the rest goes, the install succeeds
fx_reset
FAKE_DOCKER_RM_FAIL=code-quality-suite:3.0.0 inst "$CL/r1" || fail "install must succeed when one removal fails"
check "AC17 warning names the tag" out_has "could not remove code-quality-suite:3.0.0"
check "AC17 the other tags are still removed" bash -c "! test -f '$FAKE_DOCKER_DIR/code-quality-suite@2.6.0.json' && ! test -f '$FAKE_DOCKER_DIR/code-quality-suite@4.0.2.json'"
check "AC17 the failing tag stays" img_exists code-quality-suite:3.0.0
# AC18: the current version is a prerelease: the release is newer and kept on install; SNAPSHOT is older
echo 4.1.0-rc.1 >"$T/suite2/VERSION"
git init -q -b main "$CL/r6"
fx_reset
fx_image code-quality-suite:4.1.0 "$LABELLED"
fx_image code-quality-suite:4.1.0-SNAPSHOT "$LABELLED"
"$T/suite2/install.sh" "$CL/r6" >"$CL/out" 2>&1 || fail "install of a prerelease suite"
check "AC18 4.1.0 is newer than 4.1.0-rc.1: kept with a note" bash -c "grep -q 'newer than 4.1.0-rc.1' '$CL/out' && test -f '$FAKE_DOCKER_DIR/code-quality-suite@4.1.0.json'"
check "AC18 4.1.0-SNAPSHOT is older: removed" bash -c "! test -f '$FAKE_DOCKER_DIR/code-quality-suite@4.1.0-SNAPSHOT.json'"
check "AC18 look-alikes untouched" ac_lookalikes_safe
rm -rf "$CL"
export QS_HOME="$QS_HOME_MAIN"

# once per machine: setup-global, then everything is a git command
bash "$SUITE/git-integration/setup-global.sh" >sg.out 2>&1 || {
	cat sg.out
	fail "setup-global"
}
grep -q "^export QS_SUITE=\"$SUITE\"" "$HOME/.bashrc" && git config --global alias.iniciar >/dev/null &&
	git config --global alias.ayuda >/dev/null && ok "setup-global: global aliases and QS_SUITE" || {
	cat sg.out
	fail "setup-global result"
}
rm -f sg.out
mkdir "$T/nuevo"
(cd "$T/nuevo" && QS_REPO_FILES=1 git iniciar >../iniciar.out 2>&1) || {
	cat "$T/iniciar.out"
	fail "git iniciar"
}
# shellcheck disable=SC2143
(cd "$T/nuevo" && [ "$(git branch --show-current)" = develop ] && grep -q 'code-quality-suite' .git/hooks/pre-commit &&
	[ -f AGENTS.md ] && [ -f README.md ] && [ -f VERSION ] && grep -qx '/AGENTS.md' .gitignore && grep -qx '/.claude/' .gitignore &&
	grep -qx '/.quality-rules.json' .gitignore && [ -f .claude/skills/git-commands/SKILL.md ] &&
	[ -z "$(git status --porcelain --untracked-files=all | grep -E ' (AGENTS.md|CLAUDE.md|opencode.json|\.claude/|\.agents/|\.opencode/|knowledge/)')" ] &&
	git status --porcelain --untracked-files=all | grep -q ' README.md') &&
	ok "git iniciar: develop, hooks, standard files; AI files on disk but git-ignored; manual as a skill" ||
	{
		cat "$T/iniciar.out"
		(cd "$T/nuevo" && git status --short && cat .gitignore)
		fail "git iniciar result"
	}
# why capture first: grep -q stops reading and the writer gets SIGPIPE under pipefail
a1="$(cd "$T/nuevo" && git ayuda np)"
a2="$(cd "$T/nuevo" && git ayuda nueva-version)"
a3="$(cd "$T" && git ayuda)"
grep -q '^### git np' <<<"$a1" && ! grep -q '^### git nr' <<<"$a1" && grep -q 'git nv' <<<"$a2" &&
	grep -q '^## 2. Which command when' <<<"$a3" && ok "git ayuda: manual and one command (also outside a repository)" ||
	{
		echo "$a1" | head -5
		fail "git ayuda"
	}
# AI files committed by mistake: git ia takes them out of the index and keeps them on disk
(cd "$T/nuevo" && git config user.email t@example.com && git config user.name tester &&
	git add -f AGENTS.md knowledge .claude && git update-ref HEAD "$(git commit-tree "$(git write-tree)" -p HEAD -m "chore: oops")" &&
	git ia >../ia.out 2>&1 && grep -q 'taken out of the index' ../ia.out && [ -f AGENTS.md ] &&
	[ -z "$(git ls-files --cached -- AGENTS.md knowledge .claude | grep -v '^$' | head -n1)" ] &&
	git diff --cached --name-only | grep -q '^AGENTS.md$' && git ia --actualizar | grep -q 'untouched') &&
	ok "git ia: committed AI files out of the index (kept on disk); --actualizar keeps AGENTS.md" ||
	{
		cat "$T/ia.out"
		fail "git ia untrack"
	}
# agent docs folders: managed block entries (AC1), ignore matrix (AC2), untrack of tracked ones (AC4)
(cd "$T/nuevo" && grep -qx '/docs/\[0-9\]\*/' .gitignore && grep -qx '/dev_documents/' .gitignore && grep -qx '/AGENTS.md' .gitignore &&
	git check-ignore -q docs/123456/spec.md && git check-ignore -q docs/3.0.0/notes.md && git check-ignore -q dev_documents/Requirements.md &&
	! git check-ignore -q docs/GIT-WORKFLOW.md && ! git check-ignore -q docs/guide/x.md &&
	mkdir -p docs/77 dev_documents && echo a >docs/77/spec.md && echo b >dev_documents/Tests.md &&
	git add -f docs/77/spec.md dev_documents/Tests.md && git update-ref HEAD "$(git commit-tree "$(git write-tree)" -p HEAD -m "chore: oops docs")" &&
	git ia >../ia2.out 2>&1 && grep -q 'taken out of the index' ../ia2.out && [ -f docs/77/spec.md ] && [ -f dev_documents/Tests.md ] &&
	[ -z "$(git ls-files -- docs/77 dev_documents)" ]) &&
	ok "git ia: docs/<n>/ and dev_documents/ ignored, tracked ones out of the index (kept on disk)" ||
	{
		cat "$T/ia2.out"
		fail "git ia agent docs ignore"
	}
# AI layer: ai-init adds opencode.json and generates the OpenCode agents with their gateway roles
git init -q -b develop "$T/ai"
(cd "$T/ai" && bash "$SUITE/scripts/ai-init.sh" . >/dev/null) || fail "ai-init"
[ -f "$T/ai/opencode.json" ] && grep -q '^model: litellm/role-dev$' "$T/ai/.opencode/agents/developer.md" &&
	grep -q '^model: litellm/role-review$' "$T/ai/.opencode/agents/reviewer.md" &&
	grep -q '^  edit: deny$' "$T/ai/.opencode/agents/reviewer.md" &&
	! grep -q 'edit: deny' "$T/ai/.opencode/agents/developer.md" && [ -f "$T/ai/.claude/skills/quality-gate/SKILL.md" ] &&
	ok "ai-init: OpenCode agents on gateway roles, permissions from the tools, skills synced" || fail "ai-init opencode"
# dev_documents templates: created when missing, never overwritten, not even by --actualizar
D="$SUITE/ai-template/dev_documents"
# Check one dev_documents template: $1 file name, then grep patterns that must match
# Prints the file and pattern that failed and returns non-zero on the first miss
dd_check() {
	local f="$1" pat
	shift
	for pat in "$@"; do
		grep -q -- "$pat" "$D/$f" || {
			echo "dev_documents template $f lacks: $pat"
			return 1
		}
	done
}
dd_ok=1
dd_n=$(find "$D" -maxdepth 1 -type f -name "*.md" | wc -l | tr -d " ")
[ "$dd_n" -gt 0 ] || {
	dd_ok=0
	echo "no templates in ai-template/dev_documents"
}
[ -z "$(find "$D" -maxdepth 1 -type f ! -name "*.md")" ] || {
	dd_ok=0
	echo "non-markdown file in ai-template/dev_documents"
}
dd_check Requirements.md '^# Requirements$' '^### RF-001: ' '^### RNF-001: ' || dd_ok=0
dd_check Functional_Design.md '^# Functional design$' '^### CU-001: ' '^## Traceability matrix$' || dd_ok=0
dd_check Technical_Design.md '^# Technical design$' '^## Module: ' '^- Use cases: CU-001$' || dd_ok=0
dd_check Tests.md '^# Tests$' '^## CP-001: ' || dd_ok=0
for f in "$D"/*.md; do
	grep -q '^<!--$' "$f" || {
		dd_ok=0
		echo "$(basename "$f") has no format comment"
	}
done
[ "$dd_ok" = 1 ] &&
	ok "dev_documents templates: $dd_n files with title, format comment and one placeholder per type" || fail "dev_documents templates"
git init -q -b develop "$T/dd"
(cd "$T/dd" && bash "$SUITE/scripts/ai-init.sh" . >/dev/null && cmp -s dev_documents/Tests.md "$D/Tests.md" &&
	echo "# Tests filled" >dev_documents/Tests.md && bash "$SUITE/scripts/ai-init.sh" . >/dev/null &&
	bash "$SUITE/scripts/ai-init.sh" --actualizar . >"$T/dd-act.out" 2>&1 && [ "$(cat dev_documents/Tests.md)" = "# Tests filled" ] &&
	grep -q 'dev_documents/ untouched' "$T/dd-act.out" &&
	rm dev_documents/Requirements.md && bash "$SUITE/scripts/ai-init.sh" . >/dev/null &&
	cmp -s dev_documents/Requirements.md "$D/Requirements.md" && git check-ignore -q dev_documents/Tests.md &&
	[ -z "$(git status --porcelain -- dev_documents)" ]) &&
	ok "git ia: dev_documents created, recreated if deleted, filled ones kept by ia and --actualizar" || {
	cat "$T/dd-act.out" 2>/dev/null
	fail "git ia dev_documents"
}
# new end-to-end cases live in tests/hooks/cases/*.sh (one file per area)
run_cases "$SUITE/tests/hooks/cases"
echo "all hook checks passed"
