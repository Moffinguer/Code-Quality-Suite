#!/usr/bin/env bash
# git integra with branches.flow = squash (5.0.0-RC1/git/integra, ACs I1-I7): finals and
# '<F>/ORIGINAL' are rebased onto their ORIGINAL and land as ONE single-parent commit with
# Commits:, Files:, Norms:, Refs: and Squashed:; the integrated branch is deleted; OT and
# version ORIGINALs are refused; a conflict changes nothing; flow = merge keeps 4.x.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# add_commit FILE TEXT SUBJECT [BODY]: write TEXT into FILE, stage it and commit with SUBJECT
# (and BODY as a second paragraph). Exits through fail when the commit is refused.
add_commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	if [ -n "${4:-}" ]; then
		git commit -q -m "$3" -m "$4" || fail "commit $3"
	else
		git commit -q -m "$3" || fail "commit $3"
	fi
}

# parents_of REV: print the number of parents of REV.
parents_of() { git rev-list --parents -n1 "$1" | awk '{ print NF - 1 }'; }

# body_of REV: print the full message of REV.
body_of() { git log -1 --format=%B "$1"; }

# files_of REV: print only the "<status> <path>" lines of the Files: block of REV.
files_of() { body_of "$1" | awk '$0 == "Files:" { on = 1; next } on && $0 == "" { exit } on'; }

# gone BRANCH: succeed when BRANCH exists neither locally nor on origin.
gone() {
	! git rev-parse -q --verify "refs/heads/$1" >/dev/null &&
		[ -z "$(git ls-remote --heads origin "refs/heads/$1")" ]
}

# pending ORIGINAL: print the children of ORIGINAL that the library counts as not integrated
# (run on its own: git integra would integrate the ORIGINAL right away when none is pending).
pending() {
	# shellcheck source=scripts/git-flow-lib.sh
	(. "$SUITE/scripts/git-flow-lib.sh" && qs_policy_load && children_pending "$1")
}

# state: print the tips of every local branch, the current branch and the work tree status
# (to prove that a refused command changed nothing).
state() {
	git for-each-ref --format='%(refname) %(objectname)' refs/heads
	git branch --show-current
	git status --porcelain
}

V=9.0.0 OT="$V/500"
RF="$OT/RF1"
case_sandbox squash
git np "$V" >/dev/null && git np 500 >/dev/null && git np RF1 >/dev/null || fail "squash: tree $RF"
[ "$(git branch --show-current)" = "$RF/ORIGINAL" ] || fail "squash: expected to be on $RF/ORIGINAL"

# --- two siblings under RF1 --------------------------------------------------------------------
git nr a >/dev/null || fail "nr a"
add_commit a.py 'A = 1' "feat: add a" "Norms: NORM-1"
add_commit a2.py 'A2 = 1' "feat: add a2" "Norms: none"
git push -q origin "$RF/a" 2>/dev/null || fail "push a"
git checkout -q "$RF/ORIGINAL" && git nr b >/dev/null || fail "nr b"
add_commit b.py 'B = 1' "feat: add b"

# I2 / I6: the ORIGINAL waits for its children, and pre-rebase refuses to move it meanwhile
git checkout -q "$RF/ORIGINAL"
before="$(state)"
out="$(git integra --yes -m "feat(RF1): requirement" 2>&1)" && fail "squash: integrated with pending children"
grep -q "$RF/a" <<<"$out" && grep -q "$RF/b" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: ORIGINAL with pending children refused, names them" || fail "squash: pending children: $out"
# why: the hook is called directly; 'git rebase' onto an unchanged parent stops before it runs
out="$(.git/hooks/pre-rebase "$OT/ORIGINAL" "$RF/ORIGINAL" 2>&1)" &&
	fail "squash: pre-rebase let an ORIGINAL with pending children move"
grep -q 'not integrated' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: pre-rebase refuses an ORIGINAL with pending children" || fail "squash: pre-rebase: $out"

# I1 / I3 / I5: a final lands as one single-parent commit with the full message, then goes away
git checkout -q "$RF/a"
atip="$(git rev-parse HEAD)"
git integra --yes -m "feat(a): module a" -m "Why a exists." >/dev/null 2>&1 || fail "squash: integra a"
sa="$(git rev-parse HEAD)"
[ "$(git branch --show-current)" = "$RF/ORIGINAL" ] && [ "$(parents_of HEAD)" = 1 ] &&
	[ "$(git log -1 --format=%s)" = "feat(a): module a" ] &&
	ok "squash: final -> ORIGINAL as one single-parent commit (I1)" || fail "squash: integra a commit"
msg="$(body_of HEAD)"
grep -q '^Why a exists\.$' <<<"$msg" && grep -qx "Commits:" <<<"$msg" &&
	grep -q '^- [0-9a-f]* feat: add a$' <<<"$msg" && grep -q '^- [0-9a-f]* feat: add a2$' <<<"$msg" &&
	[ "$(files_of HEAD)" = "$(printf 'A a.py\nA a2.py')" ] &&
	grep -qx "Squashed: $RF/a $atip" <<<"$msg" &&
	ok "squash: body, Commits:, Files: and Squashed: in the message (I3)" || fail "squash: message: $msg"
[ "$(git log -1 --format='%(trailers:key=Refs,valueonly)' | sed '/^$/d')" = "$RF/a -> $RF/ORIGINAL" ] &&
	[ "$(git log -1 --format='%(trailers:key=Norms,valueonly)' | sed '/^$/d')" = "NORM-1" ] &&
	ok "squash: Refs: and Norms: (union) are trailers (I3)" || fail "squash: trailers: $msg"
awk '$0 == "Files:" { f = NR } /^Commits:$/ { c = NR } /^Norms: / { n = NR } /^Refs: / { r = NR }
	END { exit !(c < f && f < n && n < r) }' <<<"$msg" &&
	ok "squash: layout Commits, Files, then the trailers" || fail "squash: layout: $msg"
[ "$(git diff "$atip" HEAD --stat)" = "" ] && gone "$RF/a" &&
	ok "squash: same tree as the child; child deleted locally and on origin (I5)" || fail "squash: child kept"

# a sibling that moved: b was based on the old ORIGINAL; it is rebased and brings only its files
git checkout -q "$RF/b"
git merge-base --is-ancestor "$sa" HEAD && fail "squash: b already had a's squash"
git integra --yes -m "feat(b): module b" >/dev/null 2>&1 || fail "squash: integra b"
[ "$(git rev-parse HEAD^)" = "$sa" ] && [ "$(files_of HEAD)" = "A b.py" ] && gone "$RF/b" &&
	ok "squash: a sibling based on an older ORIGINAL is rebased; only its files" || fail "squash: sibling b"

# a sibling that moved after its squash: the recorded Squashed: sha no longer covers it
git nr c >/dev/null && add_commit c.py 'C = 1' "feat: add c" || fail "squash: c"
ctip="$(git rev-parse HEAD)"
git integra --yes -m "feat(c): module c" >/dev/null 2>&1 || fail "squash: integra c"
git branch -q "$RF/c" "$ctip" # why: as if the deletion had been declined
[ -z "$(pending "$RF/ORIGINAL")" ] && ! git merge-base --is-ancestor "$ctip" "$RF/ORIGINAL" &&
	ok "squash: a squashed child still present counts as integrated (Refs:/Squashed:)" ||
	fail "squash: squashed child pending: $(pending "$RF/ORIGINAL")"
git checkout -q "$RF/c" && add_commit c2.py 'C2 = 1' "feat: add c2"
git checkout -q "$RF/ORIGINAL"
before="$(state)"
out="$(git integra --yes -m "feat(RF1): requirement" 2>&1)" && fail "squash: a child that moved counted as integrated"
grep -q "$RF/c" <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: a child with commits after its squash is pending again (Refs:/Squashed:)" ||
	fail "squash: moved child: $out"
git checkout -q "$RF/c"
git integra --yes -m "feat(c): module c2" >/dev/null 2>&1 && [ "$(files_of HEAD)" = "A c2.py" ] && gone "$RF/c" &&
	ok "squash: the moved child goes up again with only its new commit" || fail "squash: c again"

# multi-level: the parent moves (sibling d) and RF1 synced with a merge; RF1 goes up by rebase
git checkout -q "$OT/ORIGINAL" && git nr d >/dev/null && add_commit d.py 'D = 1' "feat: add d" || fail "squash: d"
git integra --yes -m "feat(d): module d" >/dev/null 2>&1 || fail "squash: integra d"
git checkout -q "$RF/ORIGINAL" && git subir >/dev/null 2>&1 || fail "squash: subir RF1 (sync merge)"
[ "$(parents_of HEAD)" = 2 ] || fail "squash: subir on an ORIGINAL should sync with a merge"
git checkout -q "$OT/ORIGINAL" && git nr e >/dev/null && add_commit e.py 'E = 1' "feat: add e" || fail "squash: e"
git integra --yes -m "feat(e): module e" >/dev/null 2>&1 || fail "squash: integra e"
se="$(git rev-parse HEAD)"
git checkout -q "$RF/ORIGINAL"
rftip="$(git rev-parse HEAD)"
git integra --yes -m "feat(RF1): requirement one" -m "Norms: NORM-2" >/dev/null 2>&1 || fail "squash: integra RF1/ORIGINAL"
msg="$(body_of HEAD)"
[ "$(git branch --show-current)" = "$OT/ORIGINAL" ] && [ "$(parents_of HEAD)" = 1 ] && [ "$(git rev-parse HEAD^)" = "$se" ] &&
	ok "squash: <F>/ORIGINAL rebased onto its parent and squashed as one commit (I2)" || fail "squash: RF1 up"
[ "$(files_of HEAD)" = "$(printf 'A a.py\nA a2.py\nA b.py\nA c.py\nA c2.py')" ] &&
	grep -q '^- [0-9a-f]* feat(a): module a$' <<<"$msg" && grep -q '^  - [0-9a-f]* feat: add a2$' <<<"$msg" &&
	grep -q '^- [0-9a-f]* feat(b): module b$' <<<"$msg" && grep -q '^  - [0-9a-f]* feat: add c2$' <<<"$msg" &&
	[ "$(grep -c '^- ' <<<"$msg")" = 4 ] && ! grep -q 'Merge' <<<"$msg" &&
	ok "squash: nested Commits: lines, Files: of the whole level, sync merge dropped" || fail "squash: RF1 message: $msg"
grep -qx "Refs: $RF/ORIGINAL -> $OT/ORIGINAL" <<<"$msg" && grep -q "^Squashed: $RF/ORIGINAL [0-9a-f]\{40\}$" <<<"$msg" &&
	! grep -q "^Squashed: $RF/ORIGINAL $rftip$" <<<"$msg" && grep -qx "Norms: NORM-1, NORM-2" <<<"$msg" &&
	! git rev-parse -q --verify "refs/heads/$RF/ORIGINAL" >/dev/null &&
	ok "squash: Refs:, Squashed: (rebased tip), Norms: union; the ORIGINAL is deleted" || fail "squash: RF1 trailers: $msg"

# I4: the OT and version ORIGINALs go up through git release
before="$(state)"
out="$(git integra --yes -m "feat(500): OT" 2>&1)" && fail "squash: OT ORIGINAL integrated"
grep -q 'git release' <<<"$out" && [ "$(state)" = "$before" ] || fail "squash: OT refusal: $out"
git checkout -q "$V/ORIGINAL"
out="$(git integra --yes -m "feat: version" 2>&1)" && fail "squash: version ORIGINAL integrated"
grep -q 'git release' <<<"$out" && ok "squash: OT and version ORIGINALs refused, pointing to git release (I4)" ||
	fail "squash: version refusal: $out"
out="$(.git/hooks/pre-rebase "$V/ORIGINAL" "$OT/ORIGINAL" 2>&1)" && fail "squash: pre-rebase let the OT ORIGINAL move"
grep -q 'never rebase' <<<"$out" && ok "squash: pre-rebase still refuses to rebase the OT ORIGINAL" ||
	fail "squash: OT pre-rebase: $out"

# a conflict on rebase leaves everything as it was
git checkout -q "$OT/ORIGINAL" && git nr x >/dev/null && add_commit shared.txt 'from x' "feat: x shared" || fail "squash: x"
git checkout -q "$OT/ORIGINAL" && git nr y >/dev/null && add_commit shared.txt 'from y' "feat: y shared" || fail "squash: y"
git integra --yes -m "feat(y): module y" >/dev/null 2>&1 || fail "squash: integra y"
git checkout -q "$OT/x"
before="$(state)"
out="$(git integra --yes -m "feat(x): module x" 2>&1)" && fail "squash: conflicting x integrated"
gd="$(git rev-parse --absolute-git-dir)"
grep -q 'nothing was changed' <<<"$out" && [ "$(state)" = "$before" ] && [ ! -d "$gd/rebase-merge" ] && [ ! -d "$gd/rebase-apply" ] &&
	ok "squash: a rebase conflict aborts; branches and work tree unchanged" || fail "squash: conflict: $out"

# the parent checked out in another worktree: refused before anything moves
git nr z --from "$OT/ORIGINAL" >/dev/null && add_commit z.py 'Z = 1' "feat: add z" || fail "squash: z"
git worktree add -q "$CASE_REPO-wt" "$OT/ORIGINAL" >/dev/null 2>&1 || fail "worktree add"
before="$(state)"
out="$(git integra --yes -m "feat(z): module z" 2>&1)" && fail "squash: integrated into a parent checked out elsewhere"
grep -q 'another worktree' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: parent checked out in another worktree: refused, nothing changed" || fail "squash: worktree: $out"
git worktree remove --force "$CASE_REPO-wt"

# I6: pre-merge-commit refuses child -> ORIGINAL and version -> develop merge commits
git checkout -q "$OT/ORIGINAL"
out="$(git merge --no-ff -m "merge z" "$OT/z" 2>&1)" && fail "squash: child merged into its ORIGINAL"
git merge --abort >/dev/null 2>&1 || true
grep -q 'git integra' <<<"$out" && [ "$(git log -1 --format=%s)" = "feat(y): module y" ] &&
	ok "squash: pre-merge-commit refuses git merge <child> into its ORIGINAL (I6)" || fail "squash: merge child: $out"
git checkout -q develop
out="$(git merge --no-ff -m "merge version" "$V/ORIGINAL" 2>&1)" && fail "squash: version merged into develop"
git merge --abort >/dev/null 2>&1 || true
grep -q 'git publicar' <<<"$out" && [ "$(git log -1 --format=%s)" = "chore: initial" ] &&
	ok "squash: pre-merge-commit refuses <v>/ORIGINAL -> develop (I6)" || fail "squash: merge into develop: $out"
git checkout -q "$V/ORIGINAL" && add_commit v.txt 'v' "chore: version note" &&
	git checkout -q "$OT/ORIGINAL" && git merge -q --no-ff -m "chore: sync" "$V/ORIGINAL" >/dev/null 2>&1 &&
	ok "squash: parent -> ORIGINAL sync merges still allowed" || fail "squash: sync merge refused"

# --- rebased branch kept, --force under pending children, Norms: none, siblings on one file ------
# why: confirm reads /dev/tty; the cases run without a terminal, so every prompt answers "no"
case_sandbox squash
git np 9.2.0 >/dev/null && git np 700 >/dev/null || fail "squash2: tree"
OT2=9.2.0/700
git nr p >/dev/null && add_commit p.py 'P = 1' "feat: add p" || fail "squash2: p"
git push -q origin "$OT2/p" 2>/dev/null || fail "squash2: push p"
git checkout -q "$OT2/ORIGINAL" && git nr q >/dev/null && add_commit q.py 'Q = 1' "feat: add q" || fail "squash2: q"
git integra --yes -m "feat(q): module q" >/dev/null 2>&1 || fail "squash2: integra q"
[ "$(git log -1 --format='%(trailers:key=Norms,valueonly)' | sed '/^$/d')" = "none" ] &&
	ok "squash: no Norms: in the commits gives 'Norms: none'" || fail "squash2: Norms none: $(body_of HEAD)"

# declined deletion of a rebased branch: warn, print the safe command, never push by force silently
git checkout -q "$OT2/p"
otip="$(git rev-parse "origin/$OT2/p")"
out="$(git integra -m "feat(p): module p" 2>&1)" || fail "squash2: integra p: $out"
git rev-parse -q --verify "refs/heads/$OT2/p" >/dev/null && ! git merge-base --is-ancestor "origin/$OT2/p" "$OT2/p" &&
	grep -q "WARNING.*rebased" <<<"$out" && grep -q "git push --force-with-lease origin $OT2/p" <<<"$out" &&
	[ "$(git rev-parse "origin/$OT2/p")" = "$otip" ] && [ "$(git ls-remote origin "refs/heads/$OT2/p" | cut -f1)" = "$otip" ] &&
	ok "squash: a kept, rebased child warns and prints force-with-lease; origin untouched" || fail "squash2: kept: $out"
git push -q origin "$OT2/p" 2>/dev/null && fail "squash2: a plain push of the rebased branch was accepted"
QUALITY_SKIP_PARENT_CHECK=1 git push -q --force-with-lease origin "$OT2/p" >/dev/null 2>&1 && [ "$(git ls-remote origin "refs/heads/$OT2/p" | cut -f1)" = "$(git rev-parse "$OT2/p")" ] &&
	ok "squash: the printed force-with-lease command updates origin" || fail "squash2: force-with-lease"

# --force over pending children that a rebase would orphan: listed and confirmed
git checkout -q "$OT2/ORIGINAL" && git np RF4 >/dev/null && add_commit r.py 'R = 1' "feat: r on RF4" || fail "squash2: RF4"
git nr k >/dev/null && add_commit k.py 'K = 1' "feat: add k" || fail "squash2: k"
git checkout -q "$OT2/ORIGINAL" && git nr m >/dev/null && add_commit m.py 'M = 1' "feat: add m" || fail "squash2: m"
git integra --yes -m "feat(m): module m" >/dev/null 2>&1 || fail "squash2: integra m"
git checkout -q "$OT2/RF4/ORIGINAL"
before="$(state)"
out="$(git integra --force -m "feat(RF4): requirement" 2>&1)" && fail "squash2: --force without confirmation went through"
grep -q "$OT2/RF4/k" <<<"$out" && grep -q 'git subir' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: --force lists the orphaned children and stops without confirmation" || fail "squash2: force decline: $out"
out="$(git integra --force --yes -m "feat(RF4): requirement" 2>&1)" || fail "squash2: --force --yes: $out"
grep -q "WARNING.*$OT2/RF4/k" <<<"$out" && [ "$(git branch --show-current)" = "$OT2/ORIGINAL" ] &&
	ok "squash: --force --yes warns about the children and goes on" || fail "squash2: force yes: $out"

# two siblings on the SAME file: disjoint edits rebase cleanly, overlapping edits abort untouched
git checkout -q "$OT2/ORIGINAL"
printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n' >same.txt && git add same.txt && git commit -q -m "chore: same.txt" || fail "squash2: same.txt"
for s in s1 s2 s3; do git checkout -q "$OT2/ORIGINAL" && git nr "$s" >/dev/null || fail "squash2: nr $s"; done
git checkout -q "$OT2/s1" && sed -i 's/^l1$/s1/' same.txt && git commit -qam "feat: s1 edits l1"
git checkout -q "$OT2/s2" && sed -i 's/^l8$/s2/' same.txt && git commit -qam "feat: s2 edits l8"
git checkout -q "$OT2/s3" && sed -i 's/^l1$/s3/' same.txt && git commit -qam "feat: s3 edits l1"
git checkout -q "$OT2/s1" && git integra --yes -m "feat(s1): first" >/dev/null 2>&1 || fail "squash2: integra s1"
git checkout -q "$OT2/s2" && git integra --yes -m "feat(s2): second" >/dev/null 2>&1 || fail "squash2: integra s2 (disjoint edits)"
[ "$(sed -n '1p;8p' same.txt | tr '\n' ' ')" = "s1 s2 " ] && gone "$OT2/s2" &&
	ok "squash: siblings editing different lines of one file integrate cleanly" || fail "squash2: same file clean"
git checkout -q "$OT2/s3"
before="$(state)"
out="$(git integra --yes -m "feat(s3): third" 2>&1)" && fail "squash2: overlapping edit integrated"
grep -q 'nothing was changed' <<<"$out" && [ "$(state)" = "$before" ] &&
	ok "squash: siblings editing the same line of one file conflict; nothing changed" || fail "squash2: same file conflict: $out"

# --- I7: flow = merge keeps the 4.x behaviour ---------------------------------------------------
case_sandbox merge
git np 9.1.0 >/dev/null && git np 600 >/dev/null && git np RF2 >/dev/null && git nr f >/dev/null || fail "merge: tree"
add_commit f.py 'F = 1' "feat: add f"
ftip="$(git rev-parse HEAD)"
git integra -m "feat(f): module f" >/dev/null 2>&1 || fail "merge: integra f"
msg="$(body_of HEAD)"
[ "$(parents_of HEAD)" = 2 ] && git merge-base --is-ancestor "$ftip" HEAD &&
	git rev-parse -q --verify "refs/heads/9.1.0/600/RF2/f" >/dev/null &&
	awk '/^Refs: / { r = NR } /^Commits:$/ { c = NR } END { exit !(r && c && r < c) }' <<<"$msg" &&
	! grep -q '^Squashed: ' <<<"$msg" &&
	ok "merge: final integrated with merge --no-ff, 4.x message, branch kept (I7)" || fail "merge: final: $msg"
git integra -m "feat(RF2): requirement" >/dev/null 2>&1 && [ "$(parents_of HEAD)" = 2 ] &&
	[ "$(git branch --show-current)" = 9.1.0/600/ORIGINAL ] &&
	git integra -m "feat(600): OT" >/dev/null 2>&1 && [ "$(git branch --show-current)" = 9.1.0/ORIGINAL ] &&
	ok "merge: ORIGINALs merged up to the version, OT not refused (I7)" || fail "merge: ORIGINALs"
git checkout -q 9.1.0/600/ORIGINAL && git nr g >/dev/null && add_commit g.py 'G = 1' "feat: add g" &&
	git checkout -q 9.1.0/600/ORIGINAL && git merge -q --no-ff -m "chore: merge g" 9.1.0/600/g >/dev/null 2>&1 &&
	ok "merge: git merge <child> into its ORIGINAL still allowed (I7)" || fail "merge: manual merge refused"
