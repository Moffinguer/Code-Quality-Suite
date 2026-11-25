#!/usr/bin/env bash
# Case: the commit-flow guards (7.1.1 flow_guard, ACs FG1-FG6). A worktree whose git-ignored rules
# file is the generated default (flow: merge) made two merge integrations in an ORIGINAL of a squash
# project. Now git integra refuses a rules file that is missing or generated in a linked worktree
# and a flow that differs from the history of the target, and pre-push refuses a merge commit that
# integrates a child into an ORIGINAL under flow squash. Every refusal prints the safe recovery.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

V=9.6.0 OT=100 RF=RF1
F="$V/$OT/$RF"
ORIG="$F/ORIGINAL"

# set_flow FLOW: write FLOW (squash or merge) into branches.flow of the rules file of the case repo.
# Arguments: $1 flow. Returns: 0.
set_flow() {
	python3 - "$1" <<'PY'
import json, sys
p = ".quality-rules.json"
d = json.load(open(p))
d["branches"]["flow"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
}

# join_merge BRANCH SIDE REFS: the way a flow = merge integration looks, made with plumbing (no
# hook runs): a two-parent commit on BRANCH, with the tree of SIDE merged and a 'Refs:' line. The
# branch is checked out or not; its tree is reset when it is. Errors: exits 1 through fail.
join_merge() {
	local tree m
	tree="$(git merge-tree --write-tree "$1" "$2")" || fail "merge-tree $2 into $1"
	m="$(printf 'fix: integrate by merge\n\nRefs: %s\n' "$3" | git commit-tree "$tree" -p "$1" -p "$2")" || fail "commit-tree $1"
	git update-ref "refs/heads/$1" "$m"
	[ "$(git branch --show-current)" != "$1" ] || git reset -q --hard HEAD
}

# parents_of REF: print how many parents the commit REF has.
parents_of() { git log -n1 --format=%p "$1" | wc -w | tr -d ' '; }

# --- FG1, FG2, FG3 in a squash project: history squash --------------------------------------------
case_fresh_tree "$V" "$OT" "$RF"
[ "$(case_flow_eval flow_history "$ORIG")" = squash ] &&
	ok "FG1: the history of an ORIGINAL with a squash integration is squash" || fail "FG1 history"
kb="$(plumb_commit local "$ORIG" kb.txt kb "fix: known-bug commit")"
[ "$(parents_of "$kb")" = 1 ] && [ "$(case_flow_eval flow_history "$ORIG")" = squash ] &&
	ok "FG1: a single-parent commit without Refs: is no evidence (known-bug commit)" || fail "FG1 known-bug"
git push -q origin "$ORIG" 2>/dev/null && ok "FG6: a known-bug commit on an ORIGINAL passes pre-push" || fail "known-bug push"
git nr b >/dev/null || fail "nr b"
case_commit b.py 'B = 1' "feat: add b"
git checkout -q "$ORIG"
git checkout -q "$F/b"
git rebase -q "$ORIG" || fail "rebase b"
git integra -m "feat: integrate b" -m "why b" >/dev/null 2>&1 </dev/null || fail "integra b from the main checkout"
[ "$(parents_of "$ORIG")" = 1 ] && ok "FG6: the main checkout integrates with one parent (squash, flow squash)" || fail "main checkout"

# a squash history and flow merge: refused, nothing changes
git nr c >/dev/null || fail "nr c"
case_commit c.py 'C = 1' "feat: add c"
set_flow merge
before="$(case_state refs/heads)"
case_refused "history of '$ORIG' shows 'squash'" git integra -m "feat: integrate c" -m "why c"
case_refused "Safe recovery" git integra -m "feat: integrate c" -m "why c"
[ "$before" = "$(case_state refs/heads)" ] && ok "FG2/FG6: flow merge over a squash history is refused; nothing changed" ||
	fail "state changed by a refused integra"
set_flow squash

# --- FG3: a linked worktree ------------------------------------------------------------------------
git checkout -q "$ORIG"
WT="$CASE_REPO-wt"
git worktree add -q "$WT" "$F/c" || fail "worktree add"
(
	cd "$WT"
	[ ! -f .quality-rules.json ] || fail "the worktree has a rules file already"
	case_refused "no real .quality-rules.json" git integra -m "feat: integrate c" -m "why c"
	ok "FG3/FG6: a worktree without a rules file is refused"
	case_commit w.py 'W = 1' "feat: work in the worktree"
	[ -f .quality-rules.json ] && [ -f "$(git rev-parse --absolute-git-dir)/quality-suite/rules.generated" ] ||
		fail "the engine did not record the generated rules file"
	ok "FG3: the engine records the sha256 of the default rules file it creates"
	case_refused "generated" git integra -m "feat: integrate c" -m "why c"
	case_refused "Safe recovery" git integra -m "feat: integrate c" -m "why c"
	ok "FG3/FG5/FG6: a worktree with the generated default is refused with the recovery"
	case_commit w2.py 'W2 = 1' "feat: more work"
	case_refused "generated" git integra -m "feat: integrate c" -m "why c"
	ok "FG3: the mark follows the generated file when the engine updates it"
	cp "$CASE_REPO/.quality-rules.json" .quality-rules.json
	case_flow_eval flow_guard_integra "$F/c" "$ORIG" 2>/dev/null &&
		ok "FG3/FG6: with the real rules file copied in, the worktree is allowed" || fail "real rules file refused"
)
git worktree remove --force "$WT"

# --- FG4 and FG2 (merge history, flow squash) ------------------------------------------------------
case_sandbox squash
git np "$V" >/dev/null && git np "$OT" >/dev/null && git push -q origin "$V/ORIGINAL" "$V/$OT/ORIGINAL" 2>/dev/null || fail "tree"
OTO="$V/$OT/ORIGINAL"
git nr m >/dev/null || fail "nr m"
case_commit m.py 'M = 1' "feat: add m"
git push -q origin "$V/$OT/m" 2>/dev/null || fail "push m"
git checkout -q "$OTO"
join_merge "$OTO" "$V/$OT/m" "$V/$OT/m -> $OTO"
[ "$(parents_of "$OTO")" = 2 ] && [ "$(case_flow_eval flow_history "$OTO")" = merge ] &&
	ok "FG1: the history of an ORIGINAL with a merge integration is merge" || fail "FG1 merge history"
git nr n >/dev/null || fail "nr n"
case_commit n.py 'N = 1' "feat: add n"
before="$(case_state refs/heads)"
case_refused "history of '$OTO' shows 'merge'" git integra -m "feat: integrate n" -m "why n"
[ "$before" = "$(case_state refs/heads)" ] && ok "FG2/FG6: flow squash over a merge history is refused; nothing changed" ||
	fail "state changed by a refused integra"
git checkout -q "$OTO"
case_refused "merge commit" git push origin "$OTO"
case_refused "Safe recovery" git push origin "$OTO"
case_on_origin "$OTO" && [ "$(git rev-parse "origin/$OTO")" != "$(git rev-parse "$OTO")" ] &&
	ok "FG4/FG5/FG6: pre-push refuses an integration merge into an ORIGINAL under squash, with the recovery" ||
	fail "merge push not refused"

# the recovery works: reset to origin, integrate again from the main checkout
git checkout -q "$V/$OT/n"
git branch -q -f "$OTO" "origin/$OTO"
git rebase -q "$OTO" || fail "rebase n"
git integra -m "feat: integrate n" -m "why n" >/dev/null 2>&1 </dev/null || fail "integra after the recovery"
[ "$(parents_of "$OTO")" = 1 ] && git push -q origin "$OTO" 2>/dev/null &&
	ok "FG5: after the recovery the integration is one commit and pushes" || fail "recovery"

# RC1 shape already on origin: a later push is not blocked
git checkout -q "$OTO"
join_merge "$OTO" "$V/$OT/m" "$V/$OT/m -> $OTO"
git push -q --no-verify origin "$OTO" 2>/dev/null || fail "seed the merge on origin"
plumb_commit local "$OTO" later.txt later "fix: later work" >/dev/null
git push -q origin "$OTO" 2>/dev/null &&
	ok "FG4/FG6: a merge already on origin does not block a later push" || fail "RC1 shape blocks the push"

# git subir merge into a sub-ORIGINAL is allowed (the second parent is in the parent branch)
case_fresh_tree "$V" 200 "$RF"
SUB="$V/200/$RF/ORIGINAL"
plumb_commit both "$V/200/ORIGINAL" up.txt up "fix: parent moves" >/dev/null
git checkout -q "$SUB"
git subir >/dev/null 2>&1 </dev/null || true
[ "$(parents_of "$SUB")" = 2 ] && git push -q origin "$SUB" 2>/dev/null &&
	ok "FG4/FG6: git subir merging the parent into a sub-ORIGINAL pushes" || fail "subir merge push"
