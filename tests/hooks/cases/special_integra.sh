#!/usr/bin/env bash
# Cases of the integration order and refusals of the special branches (6.0.0 integra_order, ACs
# IO1-IO5): REFACTOR goes in last, SPIKE/ATTEMPT/REVIEW/QUARANTINE/CHECKPOINT/TESTING are never
# integrated or merged into an ORIGINAL, a task takes its REVIEW/QUARANTINE/CHECKPOINT with it,
# git subir syncs the types that sync, and a disabled type is an ordinary branch.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
: "${SUITE:?run the cases through tests/hooks/run.sh}"
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"

# add_commit FILE TEXT SUBJECT: write TEXT into FILE, stage it and commit with SUBJECT.
add_commit() {
	mkdir -p "$(dirname "$1")"
	printf '%s\n' "$2" >"$1"
	git add "$1"
	# why: a QUARANTINE branch needs the Generated-by trailer on every commit of its own
	case "$(git branch --show-current)" in
	*/QUARANTINE-*) git commit -q -m "$3" -m "Generated-by: test" || fail "commit $3" ;;
	*) git commit -q -m "$3" || fail "commit $3" ;;
	esac
}

# mk BRANCH FROM [FILE]: create BRANCH at FROM, switch to it and, with FILE, commit that file.
mk() {
	git checkout -q -b "$1" "$2" || fail "create $1"
	[ -z "${3:-}" ] && return 0
	# why: FORMAT takes style commits only
	case "$1" in
	*/FORMAT) add_commit "$3" "$3" "style: add $3" ;;
	*) add_commit "$3" "$3" "chore: add $3" ;;
	esac
	return 0
}

# gone BRANCH: succeed when BRANCH exists neither locally nor on origin.
gone() {
	! git rev-parse -q --verify "refs/heads/$1" >/dev/null &&
		[ -z "$(git ls-remote --heads origin "refs/heads/$1")" ]
}

# refused BRANCH PATTERN: git integra on BRANCH must fail, print PATTERN and change nothing.
refused() {
	local b="$1" out before
	git checkout -q "$b"
	before="$(case_state)"
	out="$(git integra --yes -m "feat: x" 2>&1)" && fail "git integra on $b was accepted"
	grep -q -- "$2" <<<"$out" && [ "$(case_state)" = "$before" ] || fail "git integra on $b: $out"
}

V=6.0.0 N="$V/ot1" M="$V/ot2"
case_sandbox squash
git np "$V" >/dev/null && git np ot1 >/dev/null || fail "tree $N"
git nr a >/dev/null && add_commit a.txt a "feat: add a" && git push -q origin "$N/a" || fail "task a"
git checkout -q "$N/ORIGINAL" && git nr b >/dev/null && add_commit b.txt b "feat: add b" || fail "task b"
git checkout -q "$N/ORIGINAL"

# --- IO1: REFACTOR goes in last of its node
mk "$N/REFACTOR" "$N/ORIGINAL" r.txt
git push -q origin "$N/REFACTOR" || fail "push REFACTOR"
refused "$N/REFACTOR" "$N/a"
out="$(git integra --yes -m "feat: x" 2>&1 || true)"
grep -q "$N/b" <<<"$out" && ok "IO1 REFACTOR with pending siblings refused, lists them" || fail "IO1 list: $out"
git checkout -q "$N/a" && git integra --yes -m "feat(a): a" >/dev/null 2>&1 || fail "IO1 integra a"
git checkout -q "$N/b" && git integra --yes -m "feat(b): b" >/dev/null 2>&1 || fail "IO1 integra b"
git checkout -q "$N/REFACTOR"
git integra --yes -m "refactor: tidy" >/dev/null 2>&1 || fail "IO1 integra REFACTOR"
[ "$(git rev-list --parents -n1 "$N/ORIGINAL" | awk '{ print NF - 1 }')" = 1 ] &&
	[ "$(git log -1 --format=%s "$N/ORIGINAL")" = "refactor: tidy" ] && gone "$N/REFACTOR" &&
	ok "IO1 REFACTOR rebased and squashed once the siblings are in (one parent)" || fail "IO1 squash"

# --- IO2: branches that never go up
git checkout -q "$N/ORIGINAL"
git push -q origin "$N/ORIGINAL" 2>/dev/null || true
git nr a2 >/dev/null && add_commit a2.txt a2 "feat: add a2" && git push -q origin "$N/a2" || fail "task a2"
mk "$N/REVIEW-a2" "$N/a2" rv.txt
mk "$N/QUARANTINE-a2" "$N/a2" q.txt
mk "$N/CHECKPOINT-a2" "$N/a2" c.txt
mk "$N/SPIKE" "$N/ORIGINAL" s.txt
mk "$N/t/ORIGINAL" "$N/ORIGINAL"
mk "$N/t/ATTEMPT-1" "$N/t/ORIGINAL" at.txt
git branch -q "$N/TESTING" "$N/ORIGINAL"
refused "$N/REVIEW-a2" "REVIEW"
refused "$N/QUARANTINE-a2" "QUARANTINE"
refused "$N/CHECKPOINT-a2" "CHECKPOINT"
refused "$N/SPIKE" "SPIKE"
refused "$N/t/ATTEMPT-1" "git elegir t"
refused "$N/TESTING" "TESTING"
ok "IO2 integra refused on REVIEW, QUARANTINE, CHECKPOINT, SPIKE, ATTEMPT (git elegir) and TESTING"

# a SPIKE with its own ORIGINAL: a child integrates inside it, the ORIGINAL never goes out
git checkout -q "$V/ORIGINAL" && git np ot2 >/dev/null || fail "tree $M"
mk "$M/SPIKE/ORIGINAL" "$M/ORIGINAL"
mk "$M/SPIKE/x" "$M/SPIKE/ORIGINAL" x.txt
git integra --yes -m "feat: try x" >/dev/null 2>&1 && [ "$(git branch --show-current)" = "$M/SPIKE/ORIGINAL" ] &&
	ok "IO2 inside SPIKE/ORIGINAL a child integrates normally" || fail "IO2 inside SPIKE"
refused "$M/SPIKE/ORIGINAL" "SPIKE"
ok "IO2 SPIKE/ORIGINAL is not integrated into its node"

# merges into an ORIGINAL are refused by pre-merge-commit
git checkout -q "$N/ORIGINAL"
for b in "$N/REVIEW-a2" "$N/QUARANTINE-a2" "$N/CHECKPOINT-a2" "$N/SPIKE" "$N/t/ATTEMPT-1" "$M/SPIKE/ORIGINAL"; do
	[ "$b" != "$M/SPIKE/ORIGINAL" ] || git checkout -q "$M/ORIGINAL"
	before="$(git rev-parse HEAD)"
	out="$(git merge --no-ff -m "chore: merge" "$b" 2>&1)" && fail "merge of $b into an ORIGINAL was accepted"
	git merge --abort 2>/dev/null || git reset -q --hard "$before"
	grep -q "pre-merge-commit" <<<"$out" && grep -q "never merged" <<<"$out" && [ "$(git rev-parse HEAD)" = "$before" ] ||
		fail "merge of $b: $out"
done
ok "IO2 pre-merge-commit refuses each of them into an ORIGINAL"

# --- IO3: a task takes REVIEW, QUARANTINE and CHECKPOINT with it
git checkout -q "$N/CHECKPOINT-a2" && git push -q origin "$N/CHECKPOINT-a2" "$N/REVIEW-a2" "$N/QUARANTINE-a2" 2>/dev/null || true
rtip="$(git rev-parse "$N/REVIEW-a2")"
git checkout -q "$N/a2"
out="$(git integra --yes -m "feat(a2): a2" 2>&1)" || fail "IO3 integra a2: $out"
gone "$N/a2" && gone "$N/REVIEW-a2" && gone "$N/QUARANTINE-a2" && gone "$N/CHECKPOINT-a2" &&
	grep -q "$rtip" <<<"$out" && ok "IO3 REVIEW, QUARANTINE and CHECKPOINT deleted with the task; tips printed" ||
	fail "IO3 cleanup: $out"

# --- IO4: git subir
git checkout -q "$N/ORIGINAL"
mk "$N/TESTS" "$N/ORIGINAL" src/test/tests.txt
mk "$N/FORMAT" "$N/ORIGINAL" f.txt
mk "$N/QUARANTINE-a3" "$N/ORIGINAL" q3.txt
git checkout -q "$N/ORIGINAL" && git nr a3 >/dev/null && add_commit a3.txt a3 "feat: add a3" || fail "task a3"
git push -q origin "$N/a3" || fail "push a3"
mk "$N/REVIEW-a3" "$N/a3" rv3.txt
git checkout -q "$N/ORIGINAL" && git nr a4 >/dev/null && add_commit a4.txt a4 "feat: add a4" || fail "task a4"
mk "$N/CHECKPOINT-a4" "$N/a4" c4.txt
git checkout -q "$N/ORIGINAL"
add_commit up.txt up "chore: move the ORIGINAL"
git push -q origin "$N/ORIGINAL" || fail "push ORIGINAL"
for b in "$N/TESTS" "$N/QUARANTINE-a3"; do
	git checkout -q "$b"
	git subir >/dev/null 2>&1 || fail "IO4 subir on $b"
	git merge-base --is-ancestor "$N/ORIGINAL" "$b" || fail "IO4 $b not rebased onto $N/ORIGINAL"
done
git checkout -q "$N/a3" && add_commit a3b.txt a3b "feat: more a3" && git checkout -q "$N/REVIEW-a3"
git subir >/dev/null 2>&1 || fail "IO4 subir on REVIEW"
git merge-base --is-ancestor "$N/a3" "$N/REVIEW-a3" && ok "IO4 subir syncs TESTS, QUARANTINE and REVIEW" || fail "IO4 REVIEW not on a3"
git checkout -q "$N/t/ORIGINAL" && add_commit t.txt t "feat: t" && git checkout -q "$N/t/ATTEMPT-1"
git subir >/dev/null 2>&1 || fail "IO4 subir on ATTEMPT"
git merge-base --is-ancestor "$N/t/ORIGINAL" "$N/t/ATTEMPT-1" && ok "IO4 subir syncs ATTEMPT onto the task ORIGINAL" || fail "IO4 ATTEMPT"
git checkout -q "$N/CHECKPOINT-a4"
out="$(git subir 2>&1)" || fail "IO4 subir on CHECKPOINT: $out"
grep -q "CHECKPOINT" <<<"$out" && [ -z "$(git ls-remote --heads origin "refs/heads/$N/CHECKPOINT-a4")" ] && ok "IO4 subir skips CHECKPOINT (local)" || fail "IO4 CHECKPOINT: $out"
git checkout -q "$N/FORMAT"
out="$(git subir 2>&1)" && fail "IO4 subir on FORMAT was accepted"
grep -q "git formatear" <<<"$out" && ok "IO4 subir refuses FORMAT, pointing to git formatear" || fail "IO4 FORMAT: $out"

# pre-rebase: FORMAT never rebased, nothing rebased onto CHECKPOINT/QUARANTINE/REVIEW
out="$(.git/hooks/pre-rebase "$N/ORIGINAL" "$N/FORMAT" 2>&1)" && fail "pre-rebase let FORMAT move"
grep -q "never rebased" <<<"$out" || fail "pre-rebase FORMAT: $out"
for b in CHECKPOINT-a4 QUARANTINE-a3 REVIEW-a3; do
	out="$(.git/hooks/pre-rebase "$N/$b" "$N/a4" 2>&1)" && fail "pre-rebase allowed a rebase onto $b"
	grep -q "not a base" <<<"$out" || fail "pre-rebase onto $b: $out"
done
.git/hooks/pre-rebase "$N/ORIGINAL" "$N/TESTS" >/dev/null 2>&1 && ok "pre-rebase refuses FORMAT and rebases onto CHECKPOINT, QUARANTINE, REVIEW; others pass" ||
	fail "pre-rebase refused TESTS"

# --- IO5: a disabled type is an ordinary final branch
git checkout -q "$N/ORIGINAL"
python3 - <<'PY'
import json
p = ".quality-rules.json"
d = json.load(open(p))
d.setdefault("branches", {}).setdefault("special", {})["SPIKE"] = False
json.dump(d, open(p, "w"), indent=2)
PY
git checkout -q "$N/SPIKE"
git integra --yes -m "feat: spike as final" >/dev/null 2>&1 && [ "$(git branch --show-current)" = "$N/ORIGINAL" ] && gone "$N/SPIKE" &&
	ok "IO5 a disabled type integrates as an ordinary final" || fail "IO5 SPIKE disabled"
