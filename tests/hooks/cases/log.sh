#!/usr/bin/env bash
# Case log: the Files: block in every commit message (L1-L7 of the 5.0.0-RC1 spec).
# shellcheck disable=SC2015,SC2016  # "cond && ok || fail" (ok never fails); editor stubs are single-quoted on purpose
set -euo pipefail
# shellcheck disable=SC1091
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

# msg [REV]: print the full message of REV (default HEAD).
msg() { git log -1 --format=%B "${1:-HEAD}"; }

# set_files MODE: write commit.files into the rules file.
set_files() {
	python3 - "$1" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("commit", {})["files"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
}

# L2: -m lists every staged file, subject intact, trailer still parsed
echo a >a.txt
echo b >b.txt
git add a.txt b.txt
git commit -q -m "feat: x" -m "Refs: T-1"
m="$(msg)"
[ "$(git log -1 --format=%s)" = "feat: x" ] && ok "L2 subject unchanged" || fail "L2 subject: $m"
grep -qE '^A.a\.txt$' <<<"$m" && grep -qE '^A.b\.txt$' <<<"$m" && ok "L2 files listed" || fail "L2 files: $m"
[ "$(git log -1 --format='%(trailers:key=Refs,valueonly)' | tr -d '\n')" = "T-1" ] && ok "L2 Refs trailer kept" || fail "L2 trailer: $m"
[ "$(grep -c '^Files:' <<<"$m")" = 1 ] && ok "L2 one block" || fail "L2 blocks: $m"
[ "$(grep -n '^Files:' <<<"$m" | cut -d: -f1)" -lt "$(grep -n '^Refs:' <<<"$m" | cut -d: -f1)" ] && ok "L2 block before trailers" || fail "L2 order: $m"

# L3: amend refreshes (no duplicate), against HEAD^
echo c >c.txt
git add c.txt
git commit -q --amend -m "feat: x" -m "Refs: T-1"
m="$(msg)"
[ "$(grep -c '^Files:' <<<"$m")" = 1 ] && grep -qE '^A.c\.txt$' <<<"$m" && grep -qE '^A.a\.txt$' <<<"$m" && ok "L3 amend refreshed" || fail "L3 amend: $m"
git commit -q --amend --no-edit
[ "$(grep -c '^Files:' <<<"$(msg)")" = 1 ] && ok "L3 amend --no-edit no duplicate" || fail "L3 dup: $(msg)"

# L3: empty commit
git commit -q --allow-empty -m "chore: empty"
grep -q '^(none)$' <<<"$(msg)" && ok "L3 empty commit (none)" || fail "L3 empty: $(msg)"

# L3: root commit vs empty tree
git checkout -q --orphan rootb
git rm -rfq . >/dev/null 2>&1 || true
echo r >r.txt
git add r.txt
git commit -q -m "chore: root"
grep -qE '^A.r\.txt$' <<<"$(msg)" && ok "L3 root commit" || fail "L3 root: $(msg)"
git checkout -q develop

# L3: merge --no-ff lists files vs first parent
# why: branch names outside the model are not checked by pre-merge-commit
git checkout -q -b scratch-a
echo t >t.txt
git add t.txt
git commit -q -m "feat: first parent"
git checkout -q -b scratch-b develop
echo s >s.txt
git add s.txt
git commit -q -m "feat: second parent"
git checkout -q scratch-a
git merge -q --no-ff scratch-b -m "Merge scratch-b"
m="$(msg)"
grep -qE '^A.s\.txt$' <<<"$m" && ! grep -q 't\.txt' <<<"$m" && ok "L3 merge vs first parent" || fail "L3 merge: $m"
git checkout -q develop

# L3: editor commit keeps the template and lists the files
echo e >e.txt
git add e.txt
ED="$(mktemp)"
printf '#!/bin/sh\nsed -i "1s/.*/feat: edited/" "$1"\n' >"$ED"
chmod +x "$ED"
GIT_EDITOR="$ED" git commit -q
m="$(msg)"
[ "$(git log -1 --format=%s)" = "feat: edited" ] && grep -qE '^A.e\.txt$' <<<"$m" && ok "L3 editor commit" || fail "L3 editor: $m"

# L5: block removed or edited in the editor is restored
echo f >f.txt
git add f.txt
printf '#!/bin/sh\nprintf "feat: nofiles\\n\\nbody\\n" > "$1"\n' >"$ED"
GIT_EDITOR="$ED" git commit -q 2>err.txt
grep -qE '^A.f\.txt$' <<<"$(msg)" && grep -qi 'files' err.txt && ok "L5 removed block restored" || fail "L5 removed: $(msg)"
echo g >g.txt
git add g.txt
printf '#!/bin/sh\nprintf "feat: bad\\n\\nFiles:\\nM wrong.txt\\n\\nNorms: none\\n" > "$1"\n' >"$ED"
GIT_EDITOR="$ED" git commit -q 2>err.txt
m="$(msg)"
grep -qE '^A.g\.txt$' <<<"$m" && ! grep -q wrong.txt <<<"$m" && [ "$(git log -1 --format='%(trailers:key=Norms,valueonly)' | tr -d '\n')" = none ] && ok "L5 edited block restored" || fail "L5 edited: $m"

# L4: accented file name is escaped (ASCII) and passes the charset check
echo n >"caf$(printf '\303\251').txt"
git add .
git commit -q -m "feat: accent" || fail "L4 commit rejected"
m="$(msg)"
LC_ALL=C grep -q '[^ -~]' <<<"$(printf '%s' "$m" | tr -d '\t\n')" && fail "L4 non-ASCII in message: $m"
grep -q 'caf\\303\\251' <<<"$m" && ok "L4 escaped path" || fail "L4 path: $m"

# L4b: rename
git mv a.txt a2.txt
git commit -q -m "refactor: rename"
grep -qE '^R a\.txt -> a2\.txt$' <<<"$(msg)" && ok "L1 rename" || fail "L1 rename: $(msg)"

# L7: rebase keeps exactly one correct block per commit
git checkout -q -b rb develop
echo 1 >rb1.txt
git add rb1.txt
git commit -q -m "feat: rb1"
git checkout -q develop
echo 2 >dv.txt
git add dv.txt
git commit -q -m "feat: dv"
git checkout -q rb
git rebase -q develop
m="$(msg)"
[ "$(grep -c '^Files:' <<<"$m")" = 1 ] && grep -qE '^A.rb1\.txt$' <<<"$m" && ! grep -q dv.txt <<<"$m" && ok "L7 rebase: one correct block (observed)" || fail "L7: $m"
git checkout -q develop

# L6: warn and off
set_files off
echo o >o.txt
git add o.txt
git commit -q -m "feat: off"
! grep -q '^Files:' <<<"$(msg)" && ok "L6 off: no block" || fail "L6 off: $(msg)"
set_files warn
echo w >w.txt
git add w.txt
git commit -q -m "feat: warn" 2>err.txt || fail "L6 warn must not block"
ok "L6 warn: commit accepted"
set_files block

# L8: amend on a host without /proc (QS_TEST simulates it; never active outside tests)
export QS_TEST=1 QS_TEST_NO_PROC=1
echo p >p.txt
git add p.txt
git commit -q -m "feat: p" 2>"$CASE_REPO.err"
[ ! -s "$CASE_REPO.err" ] || ! grep -q WARNING "$CASE_REPO.err" && ok "L8 normal commit: no warning" || fail "L8 warning on normal commit: $(cat "$CASE_REPO.err")"
echo q >q.txt
git add q.txt
git amend -q -m "feat: p" 2>"$CASE_REPO.err"
m="$(msg)"
grep -qE '^A.p\.txt$' <<<"$m" && grep -qE '^A.q\.txt$' <<<"$m" && ok "L8 git amend -m: block is HEAD^..index" || fail "L8 git amend: $m"
! grep -q WARNING "$CASE_REPO.err" && ok "L8 git amend: no warning" || fail "L8 amend warned: $(cat "$CASE_REPO.err")"
echo r >r2.txt
git add r2.txt
git commit -q --amend -m "feat: p" 2>"$CASE_REPO.err"
m="$(msg)"
! grep -qE '^A.p\.txt$' <<<"$m" && ok "L8 plain --amend -m reproduces the bug without /proc" || fail "L8 expected the bug: $m"
grep -q WARNING "$CASE_REPO.err" && grep -q 'git commit --amend --no-edit' "$CASE_REPO.err" && ok "L8 post-commit WARNING with the fix" || fail "L8 no warning: $(cat "$CASE_REPO.err")"
git commit -q --amend --no-edit 2>"$CASE_REPO.err"
m="$(msg)"
grep -qE '^A.p\.txt$' <<<"$m" && grep -qE '^A.r2\.txt$' <<<"$m" && ok "L8 the fix rebuilds the block" || fail "L8 fix: $m"
! grep -q WARNING "$CASE_REPO.err" && ok "L8 fixed: silent" || fail "L8 still warns: $(cat "$CASE_REPO.err")"
# off: no warning at all
set_files off
echo r3 >r3.txt
git add r3.txt
git commit -q --amend -m "feat: p" 2>"$CASE_REPO.err"
! grep -q WARNING "$CASE_REPO.err" && ok "L8 off: silent" || fail "L8 off warned"
set_files block

# L9: paths with spaces are quoted like git does
echo s >"sp ace.txt"
git add .
git commit -q -m "feat: space"
grep -qE '^A "sp ace\.txt"$' <<<"$(msg)" && ok "L9 space path quoted" || fail "L9 add: $(msg)"
git mv "sp ace.txt" "sp ace2.txt"
git commit -q -m "refactor: rename space"
grep -qE '^R "sp ace\.txt" -> "sp ace2\.txt"$' <<<"$(msg)" && ok "L9 rename with spaces" || fail "L9 rename: $(msg)"
unset QS_TEST QS_TEST_NO_PROC
