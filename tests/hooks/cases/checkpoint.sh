#!/usr/bin/env bash
# Cases of 'git checkpoint' (CK1-CK3): save points on 6.0.0/ot1/CHECKPOINT-a made with plumbing,
# the numbered list, --volver, and the branch staying local.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

CK=6.0.0/ot1/CHECKPOINT-a
git np 6.0.0 >/dev/null
git np ot1 >/dev/null
git nr a >/dev/null
printf 'one\n' >a.txt
git add a.txt
git commit -q -m "feat(a): add a" || fail "commit on a"
printf '*.log\n' >.gitignore
git add .gitignore
git commit -q -m "chore: ignore logs" || fail "commit .gitignore"

# --- CK1 save a point without touching the branch, the index or the work tree
tip="$(git rev-parse HEAD)"
printf 'two\n' >a.txt
printf 'new\n' >untracked.txt
printf 'noise\n' >debug.log
printf 'staged\n' >staged.txt
git add staged.txt
index_before="$(git ls-files -s)"
status_before="$(git status --porcelain)"
git checkpoint "step 1" >/dev/null && ok "git checkpoint saves a point" || fail "git checkpoint step 1"
git show-ref --verify -q "refs/heads/$CK" && ok "$CK exists" || fail "$CK missing"
[ "$(git rev-parse HEAD)" = "$tip" ] && ok "the task branch did not move" || fail "HEAD moved"
[ "$(git ls-files -s)" = "$index_before" ] && ok "the index did not change" || fail "index changed"
[ "$(git status --porcelain)" = "$status_before" ] && ok "the work tree did not change" || fail "status changed"
[ "$(git rev-parse "$CK^")" = "$tip" ] && ok "the first point hangs from the task tip" || fail "wrong parent"
[ "$(git show "$CK:a.txt")" = two ] && ok "tracked change in the snapshot" || fail "a.txt not in the snapshot"
[ "$(git show "$CK:untracked.txt")" = new ] && ok "untracked file in the snapshot" || fail "untracked missing"
[ "$(git show "$CK:staged.txt")" = staged ] && ok "staged file in the snapshot" || fail "staged missing"
git cat-file -e "$CK:debug.log" 2>/dev/null && fail "ignored file in the snapshot" || ok "ignored file left out"
printf 'three\n' >a.txt
rm untracked.txt
git checkpoint "step 2" >/dev/null || fail "git checkpoint step 2"
[ "$(git rev-list --count "$tip..$CK")" = 2 ] && ok "a second point extends the branch" || fail "points not chained"
git cat-file -e "$CK:untracked.txt" 2>/dev/null && fail "deleted file kept in point 2" || ok "a deleted file leaves the next point"
git checkpoint "" >/dev/null 2>&1 && fail "empty message accepted" || ok "empty message refused"

# --- CK2 list and go back
out="$(git checkpoint --lista)"
[ "$(wc -l <<<"$out")" -eq 2 ] && grep -q '^1 .*step 1$' <<<"$out" && grep -q '^2 .*step 2$' <<<"$out" && ok "--lista numbers the points" || fail "--lista: $out"
git checkpoint --volver 1 >/dev/null 2>&1 && fail "--volver on a dirty tree accepted" || ok "--volver refused on a dirty tree"
[ "$(cat a.txt)" = three ] || fail "a refused --volver changed the tree"
git checkpoint --volver 1 --force >/dev/null && ok "--volver --force restores" || fail "--volver 1 --force"
[ "$(cat a.txt)" = two ] && [ -f untracked.txt ] && [ -f staged.txt ] && ok "work tree equal to point 1" || fail "tree differs from point 1"
[ "$(git rev-parse HEAD)" = "$tip" ] && ok "--volver did not move the branch" || fail "HEAD moved by --volver"
git add -A
git commit -q -m "feat(a): work" || fail "commit before --volver 2"
git checkpoint --volver 2 >/dev/null && ok "--volver 2 on a clean tree" || fail "--volver 2"
[ "$(cat a.txt)" = three ] && [ ! -f untracked.txt ] && ok "work tree equal to point 2" || fail "tree differs from point 2"
git checkpoint --volver 9 >/dev/null 2>&1 && fail "unknown point accepted" || ok "unknown point refused"

# --- CK3 never on origin
git checkpoint "step 3" >/dev/null || fail "git checkpoint step 3"
[ -z "$(git ls-remote origin "$CK")" ] && ok "checkpoint pushes nothing to origin" || fail "$CK on origin"
git reset -q --hard
git checkout -q 6.0.0/ot1/ORIGINAL
git checkpoint "x" >/dev/null 2>&1 && fail "checkpoint on an ORIGINAL accepted" || ok "an ORIGINAL cannot be checkpointed"

# --- CK4 an attempt saves on the checkpoints of its task; other special branches stay refused
git np t >/dev/null
git branch 6.0.0/ot1/t/ATTEMPT-1 6.0.0/ot1/t/ORIGINAL
git checkout -q 6.0.0/ot1/t/ATTEMPT-1
printf 'attempt\n' >t.txt
git checkpoint "attempt step" >/dev/null && ok "git checkpoint saves on an attempt" || fail "checkpoint on an attempt"
git show-ref --verify -q refs/heads/6.0.0/ot1/CHECKPOINT-t && ok "attempt maps to CHECKPOINT-<task>" || fail "attempt did not map to 6.0.0/ot1/CHECKPOINT-t"
[ "$(git rev-parse 6.0.0/ot1/CHECKPOINT-t^)" = "$(git rev-parse 6.0.0/ot1/t/ATTEMPT-1)" ] && ok "the attempt point hangs from the attempt tip" || fail "attempt point parent"
git checkout -q 6.0.0/ot1/ORIGINAL
git branch 6.0.0/ot1/REFACTOR 6.0.0/ot1/ORIGINAL
git checkout -q 6.0.0/ot1/REFACTOR
git checkpoint "x" >/dev/null 2>&1 && fail "checkpoint on a REFACTOR accepted" || ok "another special branch is still refused"
git checkout -q 6.0.0/ot1/ORIGINAL
