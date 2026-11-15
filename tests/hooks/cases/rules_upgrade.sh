#!/usr/bin/env bash
# Case: the rules file upgrade on a suite update, acceptance criteria RU5-RU10 (6.0.0 rules_upgrade),
# plus the clean update (no old version left over). RU1-RU4 and RU8 are in tests/unit/test_rules_upgrade.py.
# Runs under tests/hooks/run.sh, which exports SUITE and T and the isolated git settings.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -uo pipefail
. "$SUITE/tests/hooks/case-lib.sh"

VERSION_NOW="$(tr -d '[:space:]' <"$SUITE/VERSION")"
POLICY_PY="$SUITE/engine/policy.py"

# strip_to_4x FILE: rewrite a rules file as a 4.x suite wrote it (no model, flow or special table).
# Arguments: FILE. Returns: python's status.
strip_to_4x() {
	python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for k in ("model", "flow", "ot_tag", "testing_leaf", "special", "publish_on_create"):
    d["branches"].pop(k, None)
json.dump(d, open(p, "w"), indent=2)
PY
}

# stamp_of REPO: print the stamp of a repository (empty when there is none). Arguments: REPO.
stamp_of() {
	local common
	common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
	cat "$common/quality-suite/suite-version" 2>/dev/null || true
}

# ---- RU10: git instalar writes the stamp
case_sandbox squash
REPO="$CASE_REPO"
[ "$(stamp_of "$REPO")" = "$VERSION_NOW" ] && ok "RU10: install wrote the stamp ($VERSION_NOW)" ||
	fail "RU10: stamp is '$(stamp_of "$REPO")', wanted $VERSION_NOW"

# ---- RU6: lazy upgrade by the next hook; once only; the stamp lives under the common dir
strip_to_4x .quality-rules.json
printf '0.0.1\n' >.git/quality-suite/suite-version
printf 'one\n' >one.txt
git add one.txt
git commit -q -m "chore: one" 2>"$T/ru6-first.err" || fail "RU6: commit failed: $(cat "$T/ru6-first.err")"
[ "$(grep -c 'rules file upgraded' "$T/ru6-first.err")" = 1 ] && ok "RU6: one summary line on stderr" ||
	fail "RU6: summary lines: $(grep -c 'rules file upgraded' "$T/ru6-first.err") in $(cat "$T/ru6-first.err")"
[ "$(stamp_of "$REPO")" = "$VERSION_NOW" ] && ok "RU6: stamp written by the hook" || fail "RU6: stamp not written"
grep -q '"model": 6' .quality-rules.json && grep -q '"on_release": "optional"' .quality-rules.json &&
	ok "RU6: rules file upgraded" || fail "RU6: rules file not upgraded"
cp .quality-rules.json "$T/ru6-before.json"
printf 'two\n' >two.txt
git add two.txt
git commit -q -m "chore: two" 2>"$T/ru6-second.err" || fail "RU6: second commit failed"
! grep -q 'rules file upgraded' "$T/ru6-second.err" && cmp -s .quality-rules.json "$T/ru6-before.json" &&
	ok "RU6: the following hook run neither rewrites nor prints" || fail "RU6: second run touched the file or printed"

# qs-run.sh --hook upgrades too (an agent edit after a suite update)
strip_to_4x .quality-rules.json
printf '0.0.1\n' >.git/quality-suite/suite-version
printf '{"tool_input": {"file_path": "%s"}}' "$PWD/two.txt" | "$SUITE/scripts/qs-run.sh" --hook 2>"$T/ru6-agent.err"
grep -q 'rules file upgraded' "$T/ru6-agent.err" && [ "$(stamp_of "$REPO")" = "$VERSION_NOW" ] &&
	ok "RU6: qs-run.sh --hook upgrades once" || fail "RU6: qs-run.sh --hook did not upgrade: $(cat "$T/ru6-agent.err")"

# linked worktree: the stamp is under the common dir, not in the worktree's own git dir
WT="$CASE_REPO-wt"
git worktree add -q "$WT" -b ru6-wt || fail "RU6: worktree add"
printf '0.0.1\n' >.git/quality-suite/suite-version
(cd "$WT" && printf 'wt\n' >wt.txt && git add wt.txt && git commit -q -m "chore: wt" 2>"$T/ru6-wt.err") || true
[ "$(stamp_of "$REPO")" = "$VERSION_NOW" ] && [ ! -e "$WT/.git/quality-suite/suite-version" ] &&
	[ -z "$(find "$REPO/.git/worktrees" -name suite-version 2>/dev/null)" ] &&
	ok "RU6: worktree stamp under the common dir" || fail "RU6: worktree stamp misplaced"

# ---- RU9: nothing to commit afterwards (the file stays ignored)
[ -z "$(git status --porcelain)" ] && ok "RU9: git status is clean after the lazy upgrade" ||
	fail "RU9: git status: $(git status --porcelain)"

# ---- RU7: an upgrade error is a warning; the stamp stays; RU8: a newer stamp is a warning
printf '{ broken' >.quality-rules.json
printf '0.0.1\n' >.git/quality-suite/suite-version
out="$(QUALITY_SUITE_DIR="$SUITE" bash -c '. "$QUALITY_SUITE_DIR/scripts/git-flow-lib.sh"; qs_suite_stamp_check; echo "rc=$?"' 2>&1)"
case "$out" in *"WARN: rules file not upgraded"*"rc=0") ok "RU7: an upgrade error is a warning (rc 0)" ;; *) fail "RU7: $out" ;; esac
[ "$(stamp_of "$REPO")" = "0.0.1" ] && ok "RU7: the stamp is unchanged (retried next time)" || fail "RU7: stamp changed"
[ "$(cat .quality-rules.json)" = "{ broken" ] && ok "RU7: the file is untouched" || fail "RU7: file changed"
printf '99.0.0\n' >.git/quality-suite/suite-version
printf '{"branches": {}}' >.quality-rules.json
out="$(QUALITY_SUITE_DIR="$SUITE" bash -c '. "$QUALITY_SUITE_DIR/scripts/git-flow-lib.sh"; qs_suite_stamp_check; echo "rc=$?"' 2>&1)"
case "$out" in *"newer than the suite"*"rc=0") ok "RU8: a newer stamp gives a warning" ;; *) fail "RU8: $out" ;; esac
[ "$(cat .quality-rules.json)" = '{"branches": {}}' ] && [ "$(stamp_of "$REPO")" = "99.0.0" ] &&
	ok "RU8: file and stamp untouched" || fail "RU8: something was written"

# ---- RU5: git actualizar-suite --yes --lazy with 3 registered repos (own QS_HOME)
export QS_HOME="$T/qs-ru5"
mkdir -p "$QS_HOME"
for n in a b c; do
	git init -q -b develop "$T/ru5-$n"
	"$SUITE/install.sh" "$T/ru5-$n" >/dev/null || fail "RU5: install $n"
done
cp "$REPO/.quality-rules.json" "$T/ru5-a/.quality-rules.json"
python3 - "$T/ru5-a/.quality-rules.json" <<'PY'
import json, sys
p = sys.argv[1]
json.dump({"branches": {"mainline": "develop"}}, open(p, "w"), indent=2)
PY
# b: a file that is already up to date; c: no file
printf '{"branches": {"mainline": "develop"}}' >"$T/ru5-b/.quality-rules.json"
python3 "$POLICY_PY" rules-upgrade "$T/ru5-b" >/dev/null || fail "RU5: prepare b"
for n in a b c; do rm -f "$T/ru5-$n/.git/quality-suite/suite-version"; done
# the older suite version image that the update must remove (clean update: no leftover versions)
OLD_IMG="code-quality-suite@2.6.0.json"
printf '{"labels": {"org.opencontainers.image.title": "code-quality-suite"}}' >"$FAKE_DOCKER_DIR/$OLD_IMG"
"$SUITE/scripts/qs-update.sh" --yes --lazy >"$T/ru5.out" 2>&1 || fail "RU5: update failed: $(cat "$T/ru5.out")"
grep -qE "^\[update\] $T/ru5-a: rules: [0-9]+ change\(s\)$" "$T/ru5.out" && grep -qE '^\[update\]   (added|migrated) ' "$T/ru5.out" &&
	ok "RU5: repo a: change count and indented changes" || fail "RU5: a: $(cat "$T/ru5.out")"
grep -qF "[update] $T/ru5-b: rules: up to date" "$T/ru5.out" && ok "RU5: repo b: up to date" || fail "RU5: b: $(cat "$T/ru5.out")"
grep -qF "[update] $T/ru5-c: no rules file (created on the first commit)" "$T/ru5.out" &&
	ok "RU5: repo c: no rules file" || fail "RU5: c: $(cat "$T/ru5.out")"
for n in a b c; do
	[ "$(stamp_of "$T/ru5-$n")" = "$VERSION_NOW" ] && ok "RU5: stamp of $n is the suite VERSION" || fail "RU5: stamp of $n"
	[ -z "$(git -C "$T/ru5-$n" status --porcelain)" ] && ok "RU9: git status of $n is clean after the update" ||
		fail "RU9: status of $n: $(git -C "$T/ru5-$n" status --porcelain)"
done
[ ! -f "$FAKE_DOCKER_DIR/$OLD_IMG" ] && ok "update: the image of the older suite version is gone (no leftover versions)" ||
	fail "update: the old image is still there"
