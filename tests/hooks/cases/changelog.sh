#!/usr/bin/env bash
# Case: qs.py release-notes writes the 5.x line format and --union merges sections.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

qs() { python3 "$SUITE/engine/qs.py" "$@"; }

base="$(git rev-parse HEAD)"
echo x >f.txt
git add f.txt
git commit -q -m "fix: tighten generated-file matching"
tip="$(git rev-parse HEAD)"
short="$(git rev-parse --short=7 HEAD)"

out="$(qs release-notes --version 5.0.0 --tip "$tip" --base "$base" --ot git 2>"$T/cl.err")"
printf '%s\n' "$out" | grep -qxF -- "- Tighten generated-file matching ($short; git)" &&
	ok "changelog: line is (hash; OT)" || fail "changelog: line format: $out"
printf '%s\n' "$out" | grep -q 'OT \|tester' &&
	fail "changelog: author or OT prefix in the line" || ok "changelog: no author, no OT prefix"
grep -q 'change without OT' "$T/cl.err" &&
	fail "changelog: warned although --ot was given" || ok "changelog: no warning with --ot"

out="$(qs release-notes --version 5.0.0 --tip "$tip" --base "$base" 2>"$T/cl.err")"
printf '%s\n' "$out" | grep -qxF -- "- Tighten generated-file matching ($short)" &&
	ok "changelog: line without OT" || fail "changelog: no-OT line: $out"
grep -q "WARN: change without OT: $short " "$T/cl.err" &&
	ok "changelog: warning for a change without OT" || fail "changelog: missing warning"

printf '### Added\n\n- A (aaaaaaa; git)\n' >"$T/s1.md"
printf '### Added\n\n- A (aaaaaaa; git)\n\n### Fixed\n\n- B (bbbbbbb; log)\n' >"$T/s2.md"
out="$(qs release-notes --version 5.0.0 --date 2026-11-02 --union "$T/s1.md" "$T/s2.md")"
[ "$(printf '%s\n' "$out" | grep -c 'A (aaaaaaa; git)')" = 1 ] &&
	ok "changelog: union drops repeated lines" || fail "changelog: union repeats: $out"
printf '%s\n' "$out" | grep -qxF -- "- B (bbbbbbb; log)" &&
	ok "changelog: union keeps every section" || fail "changelog: union lost a line"

# the gate accepts old (4.x) and new lines together
cat >CHANGELOG.md <<'EOF'
# Changelog

## 5.0.0 - 2026-11-02

### Added

- New (421994d; git)

## 4.2.1 - 2026-11-01

### Added

- Old (3b6f5f0, OT 100; Fernando Mateos)
EOF
python3 - <<'PY' && ok "changelog: validate accepts old and new lines" || fail "changelog: validate"
import os, sys
sys.path.insert(0, os.path.join(os.environ["SUITE"], "engine"))
import changelog
sys.exit(0 if changelog.validate(open("CHANGELOG.md").read()) == ([], []) else 1)
PY
