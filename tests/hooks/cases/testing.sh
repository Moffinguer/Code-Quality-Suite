#!/usr/bin/env bash
# Cases of the TESTING sandbox (git testing crear / estado / repartir and its refusals): T2-T12, O7.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

F=1.0.0/ot1
ORIG=$F/ORIGINAL
TST=$F/TESTING
MSG="TESTING is a sandbox"

# --- fixture: an ORIGINAL with a shared file, three sources and an unrelated branch
git checkout -q -b "$ORIG" develop
case_commit shared.txt base "chore: shared file"
git checkout -q -b "$F/a" "$ORIG"
case_commit a.txt a "feat: a"
git checkout -q -b "$F/b" "$ORIG"
case_commit b.txt b "feat: b"
git checkout -q -b 1.0.0/ot2/o develop
case_commit o.txt o "feat: o"
git checkout -q -b "$F/c1" "$ORIG"
case_commit shared.txt c1 "feat: c1"
git checkout -q -b "$F/c2" "$ORIG"
case_commit shared.txt c2 "feat: c2"
git checkout -q "$F/a"

# --- T2: the leaf is reserved, ignoring case
git checkout -q "$ORIG"
git nr testing >/dev/null 2>&1 && fail "T2: git nr testing accepted"
git np Testing >/dev/null 2>&1 && fail "T2: git np Testing accepted"
git nr TESTING >/dev/null 2>&1 && fail "T2: git nr TESTING accepted"
printf '1.0.0\n  ot1\n    testing\n' | git es -n >/dev/null 2>&1 && fail "T2: git es accepted a testing node"
ok "T2 reserved leaf refused"
git checkout -q "$F/a"

# --- T4: a conflicting source: nothing is created, both are named
out="$(git testing crear "$F/c1" "$F/c2" 2>&1)" && fail "T4: crear with conflicting sources worked"
grep -q "$F/c2" <<<"$out" && grep -q "$F/c1" <<<"$out" || fail "T4: message does not name both: $out"
git show-ref --verify -q "refs/heads/$TST" && fail "T4: TESTING left behind"
ok "T4 conflict creates nothing"

# --- T3: creation
orig_sha="$(git rev-parse "$ORIG")"
git testing crear "$F/a" "$F/b" 1.0.0/ot2/o >/dev/null || fail "T3: crear failed"
[ "$(git branch --show-current)" = "$F/a" ] && ok "T3 current branch unchanged" || fail "T3: branch changed"
[ "$(git rev-list --first-parent --count "$ORIG..$TST")" = 4 ] && ok "T3 3 merges + marker" || fail "T3: first-parent count"
git merge-base --is-ancestor "$orig_sha" "$TST" || fail "T3: ORIGINAL not in history"
body="$(git log -n1 --format=%B "$TST")"
[ "$(grep -c -E '^[^ ]+ [0-9a-f]{40}$' <<<"$body")" = 3 ] && ok "T3 Sources lines" || fail "T3: sources lines: $body"
grep -q "^Testing-Create: $ORIG $orig_sha$" <<<"$body" && ok "T3 Testing-Create trailer" || fail "T3: trailer"
git config --get-all "qs.testing.$F.sources" | grep -c "^$F/b " >/dev/null && ok "T3 cache set" || fail "T3: cache"
[ "$(git log -n1 --format=%s "$TST")" = "chore(testing): create" ] && ok "T3 marker subject" || fail "T3: subject"
git testing crear "$F/a" >/dev/null 2>&1 && fail "T3: second crear worked without --recrear"

# --- T5: the cache is rebuilt from the marker, also in a fresh clone
git config --unset-all "qs.testing.$F.sources"
out="$(git testing estado 2>&1)" || true
grep -q "$F/b" <<<"$out" && ok "T5 estado lists sources" || fail "T5: estado: $out"
[ "$(git config --get-all "qs.testing.$F.sources" | wc -l)" -eq 3 ] && ok "T5 cache rebuilt" || fail "T5: cache not rebuilt"
git push -q origin "$ORIG" "$F/a" "$F/b" 1.0.0/ot2/o 2>/dev/null || fail "push of the sources"
git push -q origin "$TST" 2>/dev/null || fail "T6: push of TESTING to its own name refused"
ok "T6 push to its own name allowed"
clone="$CASE_REPO-clone"
git clone -q "$CASE_REPO.git" "$clone" 2>/dev/null
[ "$(cd "$clone" && bash "$SUITE/scripts/git-testing.sh" estado "$F" | grep -c -E "$F/[ab]|ot2/o")" -ge 3 ] && ok "T5 fresh clone" || fail "T5: fresh clone"
rm -rf "$clone"

case_refused "$MSG" git merge "$TST"
[ -z "$(git status --porcelain)" ] && ok "T6 refused merge leaves a clean tree" || fail "T6: tree not clean after the refusal"
git checkout -q "$ORIG"
case_refused "$MSG" git merge "$TST"
git checkout -q "$TST"
case_refused "$MSG" git merge "$F/c1"
case_refused "$MSG" git rebase "$ORIG"
case_refused "$MSG" git integra
case_refused "$MSG" git subir
git checkout -q "$F/a"
case_refused "$MSG" git rebase "$TST"
case_refused "$MSG" git push origin "$TST:refs/heads/$ORIG"
case_refused "$MSG" git push origin "$TST:refs/heads/1.0.0/RELEASE"
git checkout -q "$ORIG"
[ "$(git rev-parse "$ORIG")" = "$orig_sha" ] && ok "T6 nothing changed" || fail "T6: ORIGINAL moved"
git checkout -q "$TST"

# --- T7: two commits on TESTING
case_commit t1.txt t1 "feat: t1"
printf 'b2\n' >b.txt
git commit -q -am "fix: b again"
list="$(git testing estado)"
[ "$(grep -c -E '^  [0-9a-f]{7,} ' <<<"$list" | tr -d ' ')" -ge 2 ] || fail "T7: listing: $list"
grep -q "feat: t1" <<<"$list" && grep -q "fix: b again" <<<"$list" || fail "T7: subjects"
grep -q "Merge\|chore(testing)" <<<"$(sed -n '/Commits on TESTING/,$p' <<<"$list")" && fail "T7: merges listed"
ok "T7 estado lists exactly the new commits"
c1="$(git rev-parse HEAD~1)"
c2="$(git rev-parse HEAD)"
git checkout -q "$F/a"

# --- T8: map each commit to a branch
before_t="$(git rev-parse "$TST")"
out="$(git testing repartir --map "$c1=$F/a" --map "$c2=$F/b" 2>&1)" || fail "T8: repartir failed: $out"
git log -n1 --format=%B "$F/a" | grep -c "cherry picked from commit $c1" >/dev/null && ok "T8 a got c1 with -x" || fail "T8: a: $(git log -n1 --format=%B "$F/a")"
git log -n1 --format=%B "$F/b" | grep -c "cherry picked from commit $c2" >/dev/null && ok "T8 b got c2" || fail "T8: b"
[ "$(git rev-parse "$TST")" = "$before_t" ] && ok "T8 TESTING unchanged" || fail "T8: TESTING moved"
[ "$(git rev-parse "origin/$F/b" 2>/dev/null)" != "$(git rev-parse "$F/b")" ] && ok "T8 nothing pushed" || fail "T8: pushed"

# --- T9: already present (patch-id): c1 again to a
a_before="$(git rev-parse "$F/a")"
out="$(git testing repartir --map "$c1=$F/a" 2>&1)" || fail "T9: repartir failed: $out"
grep -q "already present in $F/a" <<<"$out" && [ "$(git rev-parse "$F/a")" = "$a_before" ] && ok "T9 skipped, already present" || fail "T9: $out"
git testing repartir --map "$c1=$F/a" --on-applied apply >/dev/null 2>&1 || true
[ "$(git rev-parse "$F/a")" = "$a_before" ] && ok "T9 apply tried, an empty pick adds nothing" || fail "T9: apply changed a"

# --- T9: only the reverse-apply check matches (same change, different commit)
git checkout -q "$F/c1"
git branch -q -f "$F/rev" "$F/c1"
git checkout -q "$TST"
printf 'c1\n' >shared.txt
git commit -q -am "fix: shared like c1"
c3="$(git rev-parse HEAD)"
git checkout -q "$F/a"
out="$(git testing repartir --map "$c3=$F/rev" 2>&1)" || true
grep -q "already present in $F/rev" <<<"$out" && ok "T9 reverse-apply match" || fail "T9: reverse: $out"

# --- T10: a conflicting pick leaves the target and goes on
git checkout -q "$TST"
printf 'tt\n' >shared.txt
git commit -q -am "fix: shared tt"
c4="$(git rev-parse HEAD)"
case_commit t2.txt t2 "feat: t2"
c5="$(git rev-parse HEAD)"
git checkout -q "$F/a"
git checkout -q "$F/c2"
c2_before="$(git rev-parse "$F/c2")"
git checkout -q "$F/a"
out="$(git testing repartir --map "$c4=$F/c2" --map "$c5=$F/c2" 2>&1)" && fail "T10: no failure reported"
grep -q "failed in $F/c2" <<<"$out" && grep -q "applied to $F/c2" <<<"$out" && ok "T10 failed then applied" || fail "T10: $out"
[ "$(git show "$F/c2:t2.txt")" = t2 ] && [ "$(git show "$F/c2:shared.txt")" = c2 ] && ok "T10 target kept" || fail "T10: c2 content"
[ "$(git rev-list --count "$c2_before..$F/c2")" = 1 ] && ok "T10 one new commit" || fail "T10: commits"
[ -z "$(git status --porcelain)" ] && [ ! -d "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ] || fail "T10: work tree dirty"

# --- T11: interactive menu (piped input)
git checkout -q "$TST"
case_commit t3.txt t3 "feat: t3"
git checkout -q "$F/a"
mk_before="$(git rev-parse "$F/b")"
out="$(printf 's\nq\n' | git testing repartir 2>&1)" || true
grep -q "1) $F/a" <<<"$out" && grep -q "2) $F/b" <<<"$out" && grep -q "3) 1.0.0/ot2/o" <<<"$out" && ok "T11 sources numbered first" || fail "T11: menu: $out"
grep -q "skipped" <<<"$out" && grep -q "not asked (quit)" <<<"$out" && ok "T11 s skips and q stops" || fail "T11: s/q: $out"
last="$(git log -n1 --format=%H "$TST")"
out="$(printf 'o\nnope\n%s\n' "$F/b" | git testing repartir --on-applied skip 2>&1)" || true
grep -q "unknown branch 'nope'" <<<"$out" && ok "T11 unknown branch re-asked" || fail "T11: o: $out"
[ "$(git rev-parse "$F/b")" != "$mk_before" ] && git log -n1 --format=%B "$F/b" | grep -c "cherry picked from commit" >/dev/null && ok "T11 o accepts any branch" || fail "T11: o did not apply"
[ -n "$last" ] || fail "T11"

# --- T12: --recrear
git checkout -q "$TST"
case_commit t4.txt t4 "feat: t4"
git checkout -q "$F/a"
out="$(git testing crear --recrear 2>&1)" && fail "T12: recrear worked with undistributed commits"
grep -q "feat: t4" <<<"$out" && ok "T12 refused and lists them" || fail "T12: $out"
mv_orig="$(git rev-parse "$ORIG")"
t4_tip="$(git rev-parse "$TST")"
out="$(git testing crear --recrear --force 2>&1)" || fail "T12: --force failed: $out"
grep -q "old tip $t4_tip" <<<"$out" && grep -q "feat: t4" <<<"$out" && grep -q "git branch <name> $t4_tip" <<<"$out" &&
	ok "T12 --force prints the old tip, the dropped commits and the recovery" || fail "T12: force output: $out"
[ "$(git rev-parse "$TST^{tree}")" != "" ] && ! git testing estado | sed -n '/Commits on TESTING/,$p' | grep -c 'feat:' >/dev/null && ok "T12 --force re-created" || fail "T12: force"
[ "$(git log -n1 --format=%B "$TST" | grep -c "^Testing-Create: $ORIG $mv_orig")" = 1 ] && ok "T12 from the current ORIGINAL" || fail "T12: orig"
git checkout -q "$TST"
case_commit t5.txt t5 "feat: t5"
c6="$(git rev-parse HEAD)"
git checkout -q "$F/a"
git testing repartir --map "$c6=$F/a" >/dev/null || fail "T12: distribute"
git testing crear --recrear >/dev/null 2>&1 && ok "T12 recrear after distribution" || fail "T12: recrear after distribution"

# --- O7: the release helper (sourced): a clean sandbox is deletable, one with commits is not
git checkout -q "$F/a"
# shellcheck disable=SC1091
. "$SUITE/scripts/git-flow-lib.sh"
qs_policy_load
testing_release_ok "$TST" && ok "O7 clean TESTING is deleted with the tree" || fail "O7: clean"
git checkout -q "$TST"
case_commit t6.txt t6 "feat: t6"
git checkout -q "$F/a"
if testing_release_ok "$TST" 2>"$CASE_REPO.err"; then fail "O7: pending commits not detected"; fi
grep -q "feat: t6" "$CASE_REPO.err" && ok "O7 warning names the commits" || fail "O7: warning"
testing_release_ok "$F/a" && fail "O7: a normal branch matched"
ok "O7 ordinary branches are left to the release"

# --- L1: the fast-forward leak. 'git merge --ff-only TESTING' fires no merge hook
git checkout -q "$ORIG"
leak_old="$(git rev-parse "$ORIG")"
out="$(git merge --ff-only "$TST" 2>&1)" || fail "L1: the ff-only merge itself failed: $out"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$TST")" ] || fail "L1: ORIGINAL did not move to TESTING"
grep -q "contains TESTING commit" <<<"$out" && grep -q "git reset --hard $leak_old" <<<"$out" &&
	ok "L1 reference-transaction detects the ff-only merge and says how to undo it" || fail "L1: no detection: $out"
out="$(git push origin "$ORIG" 2>&1)" && fail "L1: the fast-forwarded ORIGINAL was pushed"
grep -q "TESTING" <<<"$out" && ok "L1 pre-push refuses the fast-forwarded ORIGINAL" || fail "L1: push message: $out"
git reset -q --hard "$leak_old"
# a new branch cut from TESTING is a leak too (the new ref has no old value)
out="$(git branch "$F/leak" "$TST" 2>&1)" || fail "L1: branch creation failed"
grep -q "git branch -D $F/leak" <<<"$out" && ok "L1 a branch created on TESTING is reported" || fail "L1: new branch: $out"
git branch -q -D "$F/leak"

# --- L2: no false positives
a_tip="$(git rev-parse "$F/a")"
git log "$ORIG..$F/a" --format=%B | grep -q "cherry picked from commit" || fail "L2: fixture lost its -x lines"
out="$(git merge --ff-only "$F/a" 2>&1)" || fail "L2: ff of non-TESTING work failed: $out"
grep -q "TESTING" <<<"$out" && fail "L2: false positive on ff (cherry-picks with -x): $out"
[ "$(git rev-parse HEAD)" = "$a_tip" ] || fail "L2: ff did not land"
out="$(git push origin "$ORIG" 2>&1)" || fail "L2: push of non-TESTING work refused: $out"
ok "L2 ff and push of repartir cherry-picks (-x) are not affected"
git checkout -q -b "$F/plain" "$ORIG"
case_commit plain.txt plain "feat: plain"
git checkout -q "$ORIG"
case_commit o2.txt o2 "feat: o2"
# why: a merge of the child into its ORIGINAL built by plumbing (merge-tree + commit-tree, then
# update-ref), so no hook runs; under squash such a merge is refused by hand only, and the check is
# that the reference-transaction and pre-push checks do not take a normal merge for a TESTING merge
orig_tip="$(git rev-parse "$ORIG")"
plain_tip="$(git rev-parse "$F/plain")"
tree="$(git merge-tree --write-tree "$orig_tip" "$plain_tip")" || fail "L2: merge-tree of the child"
mc="$(git commit-tree "$tree" -p "$orig_tip" -p "$plain_tip" -m "Merge branch '$F/plain' into $ORIG")"
out="$(git update-ref "refs/heads/$ORIG" "$mc" "$orig_tip" 2>&1)" || fail "L2: update-ref: $out"
git reset -q --hard "$mc" || fail "L2: work tree of the merge"
grep -q "TESTING commit" <<<"$out" && fail "L2: false positive on a merge: $out"
# why: pre-push refuses a merge into an ORIGINAL under squash (FG4); this check is about TESTING, so push it under flow merge
case_push_merge_flow origin "$ORIG" || fail "L2: push after a normal merge refused"
ok "L2 a normal merge and its push are not affected"
git checkout -q "$F/a"

# --- the manual entry: git ayuda testing
bash "$SUITE/scripts/qs-help.sh" testing | grep -c "git testing crear" >/dev/null && ok "git ayuda testing prints the manual" || fail "git ayuda testing"
