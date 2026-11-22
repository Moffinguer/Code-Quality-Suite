#!/usr/bin/env bash
# Cases of the special branch hook rules (6.0.0 hooks_rules task): paths, changelog and badge only
# on DOCS, commit types, required trailers, gate level, pre-push, suite commands not blocked.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

OUT=""

# try_commit FILE TEXT SUBJECT [BODY]: write TEXT into FILE, stage it and commit it with the
# hooks. Sets OUT to the hook output. Returns: the status of git commit.
try_commit() {
	local f="$1" text="$2" s="$3" body="${4:-}" rc=0
	mkdir -p "$(dirname "$f")"
	printf '%s\n' "$text" >"$f"
	git add -- "$f"
	if [ -n "$body" ]; then OUT="$(git commit -q -m "$s" -m "$body" 2>&1)" || rc=$?; else OUT="$(git commit -q -m "$s" 2>&1)" || rc=$?; fi
	if [ "$rc" -ne 0 ]; then
		git reset -q -- "$f" 2>/dev/null || true
		rm -f -- "$f"
	fi
	return "$rc"
}

# refused FILE TEXT SUBJECT [BODY]: the commit must be refused. Returns: 0; fails the case otherwise.
refused() { ! try_commit "$@" || fail "accepted but must be refused: $*"; }

# accepted FILE TEXT SUBJECT [BODY]: the commit must work. Returns: 0; fails the case otherwise.
accepted() { try_commit "$@" || fail "refused but must work: $* -> $OUT"; }

# says WORD: the output of the last commit must contain WORD. Returns: 0; fails the case otherwise.
says() { grep -qF -- "$1" <<<"$OUT" || fail "no '$1' in the output: $OUT"; }

# set_level LEVEL: write the project gate level into the rules file.
set_level() {
	python3 - "$1" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d["level"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
}

# set_build COMMAND: write branches.build_cmd into the rules file.
set_build() {
	python3 - "$1" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("branches", {})["build_cmd"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
}

# on BRANCH: create BRANCH from develop (or switch to it when it exists).
on() { git checkout -q "$1" 2>/dev/null || git checkout -q -b "$1" develop; }

# a valid changelog (its format is checked by the gate)
CHANGELOG_TEXT=$'# Changelog

## [1.0.0] - 2026-01-01

### Added

- first release

[1.0.0]: https://example.com/1.0.0'

# a README with a version badge between its markers and a free line, on develop (mainline)
printf '# sandbox\n\nIntro line.\n\n<!-- qs:version -->[![version 1.0.0](v1)](CHANGELOG.md)<!-- /qs:version -->\n' >README.md
git add README.md
git commit -q -m "chore: add a version badge" || fail "badge commit on develop"
git push -q origin develop

# --- HR1 paths
on 6.0.0/ot1/TESTS
refused src/main/x.java 'class X {}' "test: main code"
says "TESTS"
accepted src/test/x.java 'class XTest {}' "test: add a test"
ok "HR1 TESTS: src/main refused, src/test accepted"
on 6.0.0/DOCS
refused src/a.py 'x = 1' "docs: code"
says "DOCS"
accepted docs/a.md 'text' "docs: page"
printf 'Intro line.\n\nMore text.\n' >>README.md
git add README.md
git commit -q -m "docs: readme" >/dev/null 2>&1 && ok "HR1 DOCS: docs/a.md and README.md accepted" || fail "README on DOCS"

# --- HR2 changelog and badge only on DOCS
on 6.0.0/ot1/a
refused CHANGELOG.md "$CHANGELOG_TEXT" "docs: write the changelog"
says "CHANGELOG.md"
sed -i 's/(v1)/(v2)/' README.md
git add README.md
if git commit -q -m "docs: badge" >"$T/o" 2>&1; then fail "badge changed on a task"; fi
grep -q "badge" "$T/o" || fail "badge refusal text: $(cat "$T/o")"
git reset -q --hard
printf 'A new line outside the markers.\n' >>README.md
git add README.md
git commit -q -m "docs: a readme line" >/dev/null 2>&1 || fail "README line outside the markers refused"
ok "HR2 a task cannot change CHANGELOG.md or the badge, a README line outside the markers is fine"
on 6.0.0/DOCS
accepted CHANGELOG.md "$CHANGELOG_TEXT" "docs: changelog"
sed -i 's/(v1)/(v2)/' README.md
git add README.md
git commit -q -m "docs: badge" >"$T/o" 2>&1 && ok "HR2 DOCS may write both" || fail "badge on DOCS: $(cat "$T/o")"
# a squash made by git integra (SQUASH_MSG) is not a person's commit
git checkout -q -b 6.0.0/ORIGINAL develop
git -c merge.ff=true merge -q --squash 6.0.0/DOCS
git commit -q -m "docs: 6.0.0 documentation" >/dev/null 2>&1 && ok "HR2 the squash of DOCS into ORIGINAL is accepted" || fail "squash of DOCS"
git checkout -q develop
git branch -q -D 6.0.0/ORIGINAL

# --- HR3 commit types
on 6.0.0/MIGRATION
refused m.txt x "feat: new feature"
says "feat"
accepted m.txt x "build: java 17"
on 6.0.0/ot1/REFACTOR
refused r.txt x "feat: new feature"
refused r.txt x "fix: a bug"
says "refactor"
accepted r.txt x "style: spaces"
accepted s.txt x "refactor: tidy"
ok "HR3 REFACTOR: feat and fix refused, style accepted"
on 6.0.0/ot1/TESTS
refused src/test/t.java x "feat: new feature"
accepted src/test/t.java x "chore: housekeeping"
on 6.0.0/DOCS
refused docs/d.md x "feat: new feature"
refused docs/d.md x "fix: a bug"
refused docs/d.md x "style: spaces"
accepted docs/d.md x "docs: page"
accepted docs/e.md x "chore: housekeeping"
ok "HR3 feat refused on MIGRATION, REFACTOR, TESTS; DOCS only docs and chore"

# --- HR4 trailers
on 6.0.0/ot1/QUARANTINE-a
refused q.txt x "feat: from a model"
says "Generated-by"
accepted q.txt x "feat: from a model" "Generated-by: some-model"
ok "HR4 QUARANTINE needs Generated-by"

# --- HR5 gate level
big="$(yes 'a line of text for the large file check' | head -c 700000 || true)"
set_level format
on 6.0.0/ot1/b
accepted big.txt "$big" "feat: a large file at format level"
git reset -q --hard HEAD~1
on 6.0.0/ot1/REFACTOR
refused big.txt "$big" "refactor: a large file"
says "large"
ok "HR5 a standard-only finding passes on a task and is refused on REFACTOR (strict)"
on 6.0.0/ot1/QUARANTINE-a
refused big.txt "$big" "refactor: a large file" "Generated-by: m"
ok "HR5 QUARANTINE is strict too"
set_level standard
on 6.0.0/ot1/c
refused big.txt "$big" "feat: a large file"
on 6.0.0/ot1/CHECKPOINT-a
accepted big.txt "$big" "wip: save point of the work"
ok "HR5 CHECKPOINT runs only format and accepts a bad message"

# --- HR6 pre-push
git checkout -q 6.0.0/ot1/CHECKPOINT-a
if git push -q origin 6.0.0/ot1/CHECKPOINT-a >"$T/o" 2>&1; then fail "CHECKPOINT pushed"; fi
grep -q "never pushed" "$T/o" || fail "CHECKPOINT refusal text: $(cat "$T/o")"
ok "HR6 CHECKPOINT is never pushed"
git checkout -q 6.0.0/MIGRATION
rm -f "$T/build.log"
set_build "echo ran >>'$T/build.log'"
git push -q origin 6.0.0/MIGRATION >"$T/o" 2>&1 || fail "MIGRATION push with a good build: $(cat "$T/o")"
[ "$(cat "$T/build.log")" = ran ] && ok "HR6 MIGRATION push runs the full build" || fail "build command not run"
printf 'x\n' >j.txt
git add j.txt
git commit -q -m "build: more" >/dev/null 2>&1 || fail "second commit on MIGRATION"
set_build false
if git push -q origin 6.0.0/MIGRATION >"$T/o" 2>&1; then fail "push with a failing build"; fi
grep -q "full build failed" "$T/o" && ok "HR6 a failing full build refuses the push" || fail "build failure text: $(cat "$T/o")"
git checkout -q 6.0.0/ot1/b
printf 'x\n' >p.txt
git add p.txt
git commit -q -m "feat: plain task" >/dev/null 2>&1 || fail "commit on a task"
rm -f "$T/build.log"
set_build "echo ran >>'$T/build.log'"
git push -q origin 6.0.0/ot1/b >/dev/null 2>&1 || fail "push of a plain task"
[ ! -e "$T/build.log" ] && ok "HR6 a plain task does not run the full build" || fail "full build on a task"

# decision 14: a MIGRATION created at a published tip has no new commits: no full build
git branch 8.0.0/MIGRATION develop
rm -f "$T/build.log"
git push -q origin 8.0.0/MIGRATION >"$T/o" 2>&1 || fail "push of an empty MIGRATION: $(cat "$T/o")"
[ ! -e "$T/build.log" ] && ok "HR6 a push without new commits runs no full build" || fail "full build without new commits"

# --- HR7 suite commands are not blocked (a new sandbox: default rules, DOCS required)
case_sandbox squash
git np 7.0.0 >/dev/null 2>&1 && ok "HR7 git np makes its version commit" || fail "git np blocked"
git push -q origin 7.0.0/ORIGINAL 2>/dev/null || fail "push 7.0.0/ORIGINAL"
git np ot1 >/dev/null 2>&1 && git push -q origin 7.0.0/ot1/ORIGINAL 2>/dev/null || fail "OT ot1"
git nr work >/dev/null 2>&1 || fail "nr work"
accepted w.txt work "feat: work of the task"
git integra --yes -m "feat(w): add the work" >/dev/null 2>&1 || fail "integra of the task"
git push -q origin 7.0.0/ot1/ORIGINAL 2>/dev/null || fail "push the OT"
git release --yes >"$T/o" 2>&1 && git release --version 7.0.0 --yes >>"$T/o" 2>&1 &&
	ok "HR7 git release (OT and version) writes its commits" || fail "git release blocked: $(cat "$T/o")"
git checkout -q develop
git publicar --yes >"$T/o" 2>&1 && ok "HR7 git publicar lands the release" || fail "git publicar blocked: $(cat "$T/o")"

# --- HR1 speed: 500 staged files are matched without a fork per glob and file
(
	# shellcheck source=/dev/null
	. "$SUITE/scripts/git-flow-lib.sh"
	qs_policy_load
	files=()
	for i in $(seq 1 500); do files+=("src/test/pkg/F$i.java"); done
	files+=("src/main/Bad.java")
	start=$SECONDS
	out="$(special_check_staged 6.0.0/ot1/TESTS "${files[@]}" || true)"
	[ "$(wc -l <<<"$out")" = 1 ] && grep -q "src/main/Bad.java" <<<"$out" || exit 1
	[ $((SECONDS - start)) -lt 20 ] || exit 2
) && ok "HR1 500 staged files are checked fast" || fail "path check of 500 files (slow or wrong)"
