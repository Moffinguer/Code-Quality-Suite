#!/usr/bin/env bash
# Cases of the special branch names (6.0.0 names task): special_kind, reserved names refused by the
# creation commands, placement in valid_branch_name, parent_branch and the git arbol markers.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash
# why: the REVIEW parent rules look at origin; branches stay local here (publish on create is off)
export QS_PUBLISH=0

# lib CODE: run CODE in a subshell that has the flow library loaded with the repo policy.
# Arguments: $1 shell code. Returns: the status of CODE; its output is printed.
lib() {
	(
		# shellcheck source=/dev/null
		. "$SUITE/scripts/git-flow-lib.sh"
		qs_policy_load
		eval "$1"
	)
}

# kind BRANCH EXPECTED: special_kind must print EXPECTED (empty for an ordinary branch).
# Arguments: $1 branch, $2 expected type. Returns: 0; fails the case otherwise.
kind() {
	local got
	got="$(lib "special_kind '$1'")"
	[ "$got" = "$2" ] || fail "special_kind $1: '$got' (expected '$2')"
}

# valid BRANCH: valid_branch_name must accept it. Arguments: $1 branch. Returns: 0 or fails.
valid() { lib "valid_branch_name '$1'" >/dev/null 2>&1 || fail "refused but valid: $1"; }

# invalid BRANCH: valid_branch_name must refuse it. Arguments: $1 branch. Returns: 0 or fails.
invalid() { ! lib "valid_branch_name '$1'" >/dev/null 2>&1 || fail "accepted but invalid: $1"; }

# --- N1 special_kind
kind 6.0.0/DOCS DOCS
kind 6.0.0/MIGRATION MIGRATION
kind 6.0.0/MIGRATION/ORIGINAL MIGRATION
kind 6.0.0/MIGRATION/java17 MIGRATION
kind 6.0.0/ot1/REFACTOR REFACTOR
kind 6.0.0/ot1/a/ATTEMPT-2 ATTEMPT
kind 6.0.0/ot1/REVIEW-a REVIEW
kind 6.0.0/ot1/CHECKPOINT-a CHECKPOINT
kind 6.0.0/ot1/a ''
kind 6.0.0/ot1/ORIGINAL ''
ok "special_kind names the type of each placement"
[ -z "$(lib "QS_SP_NAMES='MIGRATION REFACTOR'; special_kind 6.0.0/DOCS")" ] && ok "special_kind: a disabled type is nothing" || fail "disabled type"
[ -z "$(lib "QS_BR_FLOW=merge; special_kind 6.0.0/DOCS")" ] && ok "special_kind: nothing under flow merge" || fail "merge flow"

# --- N3 placement
for b in 6.0.0/DOCS 6.0.0/MIGRATION/ORIGINAL 6.0.0/MIGRATION/java17 6.0.0/ot1/REFACTOR 6.0.0/ot1/REFACTOR/ORIGINAL \
	6.0.0/ot1/FORMAT 6.0.0/ot1/TESTS 6.0.0/ot1/SPIKE/ORIGINAL 6.0.0/ot1/SPIKE/x 6.0.0/ot1/a/ATTEMPT-2 \
	6.0.0/ot1/a/ATTEMPT-1/ORIGINAL 6.0.0/ot1/REVIEW-a 6.0.0/ot1/QUARANTINE-a 6.0.0/ot1/CHECKPOINT-a 6.0.0/ot1/a 6.0.0/ot1/ORIGINAL; do
	valid "$b"
done
for b in 6.0.0/ot1/DOCS 6.0.0/ot1/MIGRATION 6.0.0/FORMAT/ORIGINAL 6.0.0/ot1/CHECKPOINT-a/ORIGINAL 6.0.0/DOCS/ORIGINAL \
	6.0.0/docs 6.0.0/Docs 6.0.0/ot1/Refactor 6.0.0/ot1/review-a 6.0.0/ot1/ATTEMPT-x 6.0.0/ot1/ATTEMPT-1 6.0.0/ot1/REVIEW- \
	6.0.0/ot1/FORMAT/x 6.0.0/MIGRATION/DOCS 6.0.0/ot1/SPIKE/DOCS 6.0.0/ot1/Spike/x 6.0.0/ot1/a/Attempt-1; do
	invalid "$b"
done
ok "valid_branch_name: exact names in their place, refused elsewhere and in other case"
lib "QS_SP_NAMES='MIGRATION'; valid_branch_name 6.0.0/ot1/docs" >/dev/null && ok "a type disabled frees its name" || fail "disabled type name"
lib "QS_BR_FLOW=merge; valid_branch_name 6.0.0/ot1/DOCS" >/dev/null && ok "flow merge keeps 4.x names" || fail "merge flow name"
lib "QS_SP_NAMES='DOCS'; valid_branch_name 6.0.0/ot1/Docs" >/dev/null 2>&1 && fail "Docs accepted" || ok "ordinary segment in another case of an enabled name refused"

# --- N2 creation commands
git np 6.0.0 >/dev/null
git np ot1 >/dev/null
for n in docs Docs DOCS Refactor tests review-a ATTEMPT-1 Checkpoint-b quarantine-x migration spike format; do
	out="$(git nr "$n" 2>&1)" && fail "git nr $n created a branch"
	grep -q "reserved for" <<<"$out" && grep -q "use 'git " <<<"$out" || fail "git nr $n: $out"
done
out="$(git np review-a 2>&1)" && fail "git np review-a created a branch"
grep -q "git revision" <<<"$out" && ok "git nr/np refuse special names naming the creation command" || fail "git np review-a: $out"
git nr login >/dev/null && ok "git nr login still works" || fail "git nr login"
git checkout -q 6.0.0/ot1/ORIGINAL
before="$(git for-each-ref --format='%(refname)' refs/heads | sort)"
out="$(printf '6.0.0/ot1\n   tests\n      a\n' | git es 2>&1)" && fail "git es with a tests node was accepted"
grep -q "reserved for TESTS" <<<"$out" && grep -q "git tests" <<<"$out" || fail "git es: $out"
[ "$before" = "$(git for-each-ref --format='%(refname)' refs/heads | sort)" ] && ok "git es refuses a tests node and creates nothing" || fail "git es created branches"
# a disabled type frees its name for git nr
lib "QS_SP_NAMES='MIGRATION REFACTOR'; ! special_refusal docs >/dev/null && special_refusal refactor >/dev/null" && ok "disabled DOCS frees 'docs'; REFACTOR still reserved" || fail "disabled type refusal"

# --- parent_branch
par() { lib "parent_branch '$1'"; }
[ "$(par 6.0.0/DOCS)" = 6.0.0/ORIGINAL ] && [ "$(par 6.0.0/MIGRATION/ORIGINAL)" = 6.0.0/ORIGINAL ] &&
	[ "$(par 6.0.0/MIGRATION/java17)" = 6.0.0/MIGRATION/ORIGINAL ] && [ "$(par 6.0.0/ot1/REFACTOR)" = 6.0.0/ot1/ORIGINAL ] &&
	[ "$(par 6.0.0/ot1/REFACTOR/x)" = 6.0.0/ot1/REFACTOR/ORIGINAL ] && [ "$(par 6.0.0/ot1/a/ATTEMPT-2)" = 6.0.0/ot1/a/ORIGINAL ] &&
	[ "$(par 6.0.0/ot1/QUARANTINE-a)" = 6.0.0/ot1/ORIGINAL ] && ok "parent_branch of special branches" || fail "parent_branch"
[ "$(par 6.0.0/ot1/REVIEW-login)" = 6.0.0/ot1/login ] && [ "$(par 6.0.0/ot1/CHECKPOINT-login)" = 6.0.0/ot1/login ] &&
	ok "REVIEW and CHECKPOINT hang from the task" || fail "parent_branch of REVIEW"
git checkout -q 6.0.0/ot1/login
git branch -m 6.0.0/ot1/login 6.0.0/ot1/login/ORIGINAL
[ "$(par 6.0.0/ot1/REVIEW-login)" = 6.0.0/ot1/login/ORIGINAL ] && ok "REVIEW of a task with attempts hangs from its ORIGINAL" || fail "parent_branch REVIEW attempts"
[ -z "$(par 6.0.0/ot1/DOCS)" ] && ok "parent_branch of a misplaced name is empty" || fail "parent_branch misplaced"

# --- N5 git arbol markers
for b in 6.0.0/DOCS 6.0.0/ot1/REFACTOR 6.0.0/ot1/FORMAT 6.0.0/ot1/TESTS 6.0.0/ot1/SPIKE 6.0.0/ot1/login/ATTEMPT-1 \
	6.0.0/ot1/REVIEW-login 6.0.0/ot1/QUARANTINE-login 6.0.0/ot1/CHECKPOINT-login 6.0.0/ot1/TESTING; do
	git branch -q --no-track "$b" 6.0.0/ot1/ORIGINAL
done
out="$(git arbol 6.0.0 2>&1)"
for m in docs refactor format tests spike attempt review quarantine checkpoint testing; do
	grep -qE -- "-[ ]6\.0\.0/.*\[$m\]" <<<"$out" || fail "git arbol lacks [$m]: $out"
done
grep -q "MIGRATION open" <<<"$out" && fail "MIGRATION warning without a MIGRATION: $out"
ok "git arbol marks every special type"
git branch -q --no-track 6.0.0/MIGRATION/ORIGINAL 6.0.0/ORIGINAL
out="$(git arbol 6.0.0 2>&1)"
grep -q "6.0.0: MIGRATION open: nothing else can be created" <<<"$out" && grep -q "MIGRATION/ORIGINAL.*\[migration\]" <<<"$out" &&
	ok "git arbol warns about an open MIGRATION" || fail "MIGRATION warning: $out"

# --- N4 MIGRATION lock (6.0.0/MIGRATION/ORIGINAL exists locally)
git checkout -q 6.0.0/ot1/ORIGINAL
# locked CMD...: the command must fail and name MIGRATION.
# Arguments: the command. Returns: 0 when refused naming MIGRATION; fails the case otherwise.
locked() {
	local out
	out="$("$@" 2>&1)" && fail "not refused: $*"
	grep -q "MIGRATION" <<<"$out" || fail "refusal without MIGRATION: $* -> $out"
}
locked git np ot2
locked git nr x
locked git nv 6.0.0
out="$(printf '6.0.0/ot9/a\n' | git es 2>&1)" && fail "git es in a locked version"
grep -q "MIGRATION" <<<"$out" || fail "git es lock message: $out"
locked git testing crear 6.0.0/ot1/DOCS --nivel 6.0.0/ot1
lib "special_migration_lock 6.0.0 6.0.0/DOCS" >/dev/null || fail "git docs lock helper"
ok "MIGRATION lock: np, nr, es, nv, testing crear and docs refused"
git checkout -q 6.0.0/MIGRATION/ORIGINAL
git nr java17 >/dev/null && [ "$(git branch --show-current)" = 6.0.0/MIGRATION/java17 ] && ok "git nr java17 works inside MIGRATION" || fail "nr inside MIGRATION"
git checkout -q develop
git np 7.0.0 >/dev/null && git np ot1 >/dev/null && ok "another version is free" || fail "other version locked"
# origin-only MIGRATION
git checkout -q develop
git np 8.0.0 >/dev/null
git push -q origin 8.0.0/ORIGINAL:refs/heads/8.0.0/MIGRATION/ORIGINAL
git show-ref --verify -q refs/heads/8.0.0/MIGRATION/ORIGINAL && fail "fixture: MIGRATION is local"
locked git np ot1
ok "MIGRATION only on origin locks the version"

# --- N6 post-checkout line
out="$(git checkout 6.0.0/DOCS 2>&1)"
grep -q '^\[special\] DOCS: ' <<<"$out" || fail "post-checkout special line: $out"
out="$(git checkout 6.0.0/ot1/ORIGINAL 2>&1)"
grep -q '\[special\]' <<<"$out" && fail "post-checkout line on a normal branch: $out"
ok "post-checkout prints one [special] line on special branches only"

# --- N7 qs-alias header
mkdir -p "$T/suite-n7/scripts"
printf '#!/usr/bin/env bash\n# qs-alias: zeta zeta-largo\n' >"$T/suite-n7/scripts/git-zeta.sh"
lib "configure_repo '$T/suite-n7'"
[ "$(git config alias.zeta)" = "!bash '$T/suite-n7/scripts/git-zeta.sh'" ] && [ -n "$(git config alias.zeta-largo)" ] &&
	ok "configure_repo registers scripts with a qs-alias header" || fail "qs-alias"
lib "configure_repo '$SUITE'"
# a header may not shadow a git command, a suite alias or another script's alias
mkdir -p "$T/suite-n7b/scripts"
printf '#!/usr/bin/env bash\n# qs-alias: commit nr dup mine\n' >"$T/suite-n7b/scripts/git-a.sh"
printf '#!/usr/bin/env bash\n# qs-alias: dup mine2\n' >"$T/suite-n7b/scripts/git-b.sh"
git config alias.nr "!bash '$SUITE/scripts/git-rama.sh' nueva-final"
out="$(lib "configure_repo '$T/suite-n7b'" 2>&1)"
[ -z "$(git config alias.commit)" ] && [ "$(git config alias.nr)" = "!bash '$T/suite-n7b/scripts/git-rama.sh' nueva-final" ] &&
	grep -q "'commit' is a git command" <<<"$out" && grep -q "'nr' is already defined" <<<"$out" ||
	fail "qs-alias shadowing: $out"
[ -z "$(git config alias.dup)" ] && grep -q "'dup' claimed by both .*git-a.sh and .*git-b.sh" <<<"$out" &&
	[ "$(git config alias.mine)" = "!bash '$T/suite-n7b/scripts/git-a.sh'" ] && [ "$(git config alias.mine2)" = "!bash '$T/suite-n7b/scripts/git-b.sh'" ] &&
	ok "qs-alias skips git commands, suite aliases and duplicate claims with a warning" || fail "qs-alias duplicates: $out"
lib "configure_repo '$SUITE'"
git config --unset alias.mine
git config --unset alias.mine2

# --- git nv --arbol-completo leaves the special branches behind
out="$(git nv 9.0.0 --from 6.0.0/ot1/ORIGINAL --arbol-completo -n 2>&1)"
grep -q "9.0.0/ot1/" <<<"$out" && ! grep -qE "MIGRATION|DOCS|REFACTOR|REVIEW|ATTEMPT|CHECKPOINT|QUARANTINE" <<<"$out" &&
	ok "nv --arbol-completo copies no special branch" || fail "nv --arbol-completo: $out"
