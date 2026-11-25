#!/usr/bin/env bash
# ci-check.sh - run the suite in CHECK mode (never modifies) on the files changed against a
# base. Meant for CI. Uses the same image, rules file and engine as the hooks.
#   ci-check.sh [base_ref]        default origin/main
#   ALL=1 ci-check.sh             every tracked file (nightly)
# In CI, commit .quality-rules.json or provide it (QS_RULES_FILE=path) for identical results.
set -euo pipefail
QUALITY_SUITE_DIR="${QUALITY_SUITE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
. "${QUALITY_SUITE_DIR}/scripts/qs-common.sh"
BASE="${1:-origin/main}"
REPO_ROOT="$(qs_repo_root)"
STATE="$(qs_state_dir)"
mkdir -p "$STATE"
LIST="${STATE}/ci-files.lst"

if [ "${ALL:-0}" = "1" ]; then
	git -C "$REPO_ROOT" ls-files -z >"$LIST"
else
	# why: a missing base (shallow clone) must fail loudly, not pass with "nothing to verify"
	qs_ref_exists "${BASE}^{commit}" ||
		{
			echo "[ci] base '$BASE' not found (fetch it, or use fetch-depth: 0)" >&2
			exit 2
		}
	mb="$(git merge-base HEAD "$BASE")"
	git -C "$REPO_ROOT" diff --name-only -z --diff-filter=ACMR "$mb" HEAD >"$LIST"
fi
qs_read_list "$LIST"
[ "${#QS_FILES[@]}" -eq 0 ] && {
	echo "[ci] nothing to verify"
	exit 0
}
echo "[ci] verifying ${#QS_FILES[@]} file(s) in check mode..."

QS_NO_PROMPT=1 "${QUALITY_SUITE_DIR}/scripts/ensure-langs.sh" "$QUALITY_SUITE_DIR" /dev/null "$QUALITY_SUITE_IMAGE" --from "$LIST"
cp "$LIST" "${STATE}/files.lst"
RULES=()
if [ -n "${QS_RULES_FILE:-}" ] && [ -f "$QS_RULES_FILE" ]; then
	RULES=(-v "$(qs_hostpath "$(cd "$(dirname "$QS_RULES_FILE")" && pwd)/$(basename "$QS_RULES_FILE")"):/qs-rules.json:ro"
	-e QS_RULES=/qs-rules.json)
fi
qs_docker_opts
docker run "${QS_DOCKER_OPTS[@]}" -e QUALITY_MODE=check -e QS_STATE=/qs-state -e QS_FILES_FROM=/qs-state/files.lst \
	${RULES[@]+"${RULES[@]}"} \
	-v "$(qs_hostpath "$REPO_ROOT"):/workspace:ro" -v "$(qs_hostpath "$STATE"):/qs-state" -w /workspace \
	"$QUALITY_SUITE_IMAGE" run
