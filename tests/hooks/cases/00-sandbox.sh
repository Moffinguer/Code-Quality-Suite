#!/usr/bin/env bash
# Sample case: the sandbox helper gives a fresh repo with the suite installed.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox merge
[ -x .git/hooks/pre-commit ] && ok "sandbox: hooks installed" || fail "sandbox: no hooks"
grep -q '"flow": "merge"' .quality-rules.json && ok "sandbox: flow pinned" || fail "sandbox: flow"
[ "$(git branch --show-current)" = develop ] && ok "sandbox: on develop" || fail "sandbox: branch"
