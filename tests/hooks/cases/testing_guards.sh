#!/usr/bin/env bash
# Cases of the TESTING guards behind the copy and cache checks:
#   G1 the patch-id cache file of a tip that is no longer a TESTING tip is pruned on the next write;
#   G2 a failed git command (log or patch-id) is never cached as an empty list;
#   G3 a branch named just TESTING is an ordinary branch, not a sandbox;
#   G4 the copy refusal names its two ways out, and both work.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

F=1.0.0/ot1
ORIG=$F/ORIGINAL
TST=$F/TESTING
CACHE=.git/quality-suite

# --- fixture: an ORIGINAL, a TESTING built on it with one commit of its own
case_testing_tree

# --- G1: the cache of an old tip is pruned when a new tip is written; a stray file too
case_flow_eval testing_patch_ids "$(git rev-parse "$TST")" >/dev/null || fail "G1: patch-ids of the first tip"
tip1="$(git rev-parse "$TST")"
[ -f "$CACHE/tst-pids-$tip1" ] || fail "G1: no cache for the first tip"
fake=1111111111111111111111111111111111111111
: >"$CACHE/tst-pids-$fake"
case_commit t2.txt t2 "feat: t2"
tip2="$(git rev-parse "$TST")"
case_flow_eval testing_patch_ids "$tip2" >/dev/null || fail "G1: patch-ids of the second tip"
if [ ! -e "$CACHE/tst-pids-$tip1" ] && [ ! -e "$CACHE/tst-pids-$fake" ] && [ -f "$CACHE/tst-pids-$tip2" ]; then
	ok "G1 old and unknown cache files pruned, the live tip kept"
else
	fail "G1: cache files after the write: $(ls "$CACHE")"
fi

# --- G2: a failed git command is not cached as an empty list, and a later good run is
case_commit t3.txt t3 "feat: t3"
tip3="$(git rev-parse "$TST")"
for mode in log patch-id; do
	# why: the wrapper only fails the command named by the mode; everything else is real git
	if (
		# shellcheck disable=SC1091
		. "$SUITE/scripts/git-flow-lib.sh"
		qs_policy_load
		# git ARGS...: wrapper over git that fails the command named by QS_FAIL (log or patch-id).
		# Arguments: the git arguments. Return: 1 for the failing command (log with -p, or patch-id
		# after it reads stdin), otherwise the status of the real git run through command git.
		git() {
			case "$1:$QS_FAIL" in
			patch-id:patch-id)
				cat >/dev/null
				return 1
				;;
			log:log)
				case " $* " in *" -p "*) return 1 ;; esac
				;;
			esac
			command git "$@"
		}
		QS_FAIL="$mode" testing_patch_ids "$tip3" >/dev/null
	); then
		fail "G2: a failed $mode was reported as success"
	fi
	[ -e "$CACHE/tst-pids-$tip3" ] && fail "G2: a failed $mode was cached"
done
n="$(case_flow_eval testing_patch_ids "$tip3" | wc -l | tr -d ' ')"
[ "$n" -ge 3 ] && [ -s "$CACHE/tst-pids-$tip3" ] && ok "G2 failures not cached, the next good run is" ||
	fail "G2: good run listed $n patch-ids"

# --- G3: a branch named just TESTING is not a sandbox (the ** glob matches it, the guard must not)
git branch TESTING "$ORIG" || fail "G3: cannot create a branch named TESTING"
case_flow_eval is_testing_branch TESTING && fail "G3: a branch named TESTING is a sandbox"
case_flow_eval is_testing_branch "$TST" || fail "G3: the level TESTING is not a sandbox"
lines="$(case_flow_eval testing_local_refs)"
grep -qx "refs/heads/TESTING" <<<"$lines" && fail "G3: a bare TESTING listed as a sandbox"
grep -qx "refs/heads/$TST" <<<"$lines" || fail "G3: the level TESTING not listed: $lines"
ok "G3 a branch named TESTING is an ordinary branch"
git branch -q -D TESTING

# --- G4: a cherry-pick without -x is refused, and the message names both ways out
git checkout -q "$TST"
t1="$(git log -n1 --format=%H --grep='^feat: t1$' "$TST")"
git checkout -q -b "$F/cp" "$ORIG"
git cherry-pick "$t1" >/dev/null || fail "G4: cherry-pick"
out="$(git push origin "$F/cp" 2>&1)" && fail "G4: the copy was pushed"
grep -qF "(cherry picked from commit $t1)" <<<"$out" && grep -q "git testing repartir" <<<"$out" &&
	grep -qF -- "--map $t1=$F/cp --on-applied skip" <<<"$out" || fail "G4: the way out is not named: $out"
ok "G4 the copy refusal names both ways out"

# way out 1: the message says where the change comes from
printf 'feat: t1\n\n(cherry picked from commit %s)\n' "$t1" >"$CASE_REPO.msg"
git commit -q --amend -F "$CASE_REPO.msg" || fail "G4: amend"
git push -q origin "$F/cp" 2>/dev/null || fail "G4: the message with the cherry-pick line was refused"
ok "G4 way out 1: the cherry-pick line is accepted"

# way out 2: the copy is recorded as distributed, with the command the refusal names
git checkout -q -b "$F/cp2" "$ORIG"
git cherry-pick "$t1" >/dev/null || fail "G4: second cherry-pick"
out="$(git testing repartir --map "$t1=$F/cp2" --on-applied skip 2>&1)" || fail "G4: repartir: $out"
grep -qF "already present in $F/cp2" <<<"$out" || fail "G4: repartir did not record it: $out"
git config --get-all "qs.testing.$F.distributed" | grep -qF "$t1 $F/cp2" || fail "G4: not recorded as distributed"
git push -q origin "$F/cp2" 2>/dev/null || fail "G4: the distributed copy was refused"
ok "G4 way out 2: the recorded command accepts the copy"
