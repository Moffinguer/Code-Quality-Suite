# Hook case files

`tests/hooks/run.sh` ends by running every `cases/*.sh` in name order, each as its own bash
process, stopping at the first failure (`FAIL: case <name>`). An empty directory is fine.

To add cases (one file per branch or area, `cases/<name>.sh`, so run.sh is never edited):

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$SUITE/tests/hooks/case-lib.sh"   # ok, fail, case_sandbox
case_sandbox merge                   # fresh repo + origin, suite installed; or squash / none
# ... checks: cond && ok "what" || fail "what"
```

Environment from run.sh: `SUITE`, `T` (temp dir), fake docker on PATH, isolated git config.
Set `branches.flow` explicitly where the flow matters. Every shell function needs a doc comment.
