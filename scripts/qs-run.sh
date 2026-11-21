#!/usr/bin/env bash
# qs-run.sh - run the quality gate on given files of the working tree, outside a commit.
# Used by AI agents right after they edit a file (Claude Code PostToolUse hook, Codex/Gemini
# instructions in AGENTS.md) so they see formatter/linter findings before committing.
#   qs-run.sh [--check] FILE...      default: fix mode (formats in place, then reports)
#   qs-run.sh --hook                 Claude Code hook: reads the edited path from the JSON on stdin
#   qs-run.sh --encoding [--fix] [FILE...]   (git encoding) encoding + mojibake report of the files,
#                                    default: every changed or new file; --fix repairs them in place
# Exit: 0 clean, 1 findings (printed), 2 in --hook mode = findings fed back to the agent.
set -euo pipefail
HOOK=0 MODE=fix START="$PWD" ENC=0 ENCFIX=0
case "${1:-}" in
--hook)
	HOOK=1
	shift
	;;
--check)
	MODE=check
	shift
	;;
--encoding)
	ENC=1
	shift
	[ "${1:-}" = --fix ] && {
		ENCFIX=1
		shift
	}
	;;
esac
# why: git aliases run from the repository root; GIT_PREFIX is where the user typed the command
[ -n "${GIT_PREFIX:-}" ] && START="$(cd "${GIT_PREFIX}" && pwd)"

files=()
if [ "$HOOK" = 1 ]; then
	# why python: Git Bash has no jq; python3 is optional, so fall back to a regex on the JSON
	json="$(cat)"
	f="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path",""))' 2>/dev/null ||
		printf '%s' "$json" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's/\\\\/\\/g')"
	[ -n "$f" ] || exit 0
	# why: on Windows the agent passes C:\dir\file; Git Bash tools need /c/dir/file
	case "$f" in [A-Za-z]:\\* | [A-Za-z]:/*) command -v cygpath >/dev/null 2>&1 && f="$(cygpath -u "$f")" ;; esac
	[ -f "$f" ] || exit 0
	# why: the repository is the one holding the file, not the hook's cwd (agents in a worktree)
	cd "$(dirname "$f")"
	files=("$f")
else
	files=("$@")
fi
[ "${#files[@]}" -gt 0 ] || [ "$ENC" = 1 ] || {
	echo "usage: qs-run.sh [--check] FILE... | --hook | --encoding [--fix] [FILE...]" >&2
	exit 2
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
	echo "[qs-run] not inside a git repository" >&2
	exit 0
}
if [ "$ENC" = 1 ] && [ "${#files[@]}" -eq 0 ]; then
	# why: what is about to be committed: changed (staged or not) and new files
	cd "$ROOT"
	START="$PWD"
	while IFS= read -r -d '' f; do files+=("$f"); done < <(
		{
			git diff -z --name-only --diff-filter=ACMR HEAD 2>/dev/null || git ls-files -z
			git ls-files -z --others --exclude-standard
		} | sort -zu
	)
	[ "${#files[@]}" -gt 0 ] || {
		echo "[quality-suite] encoding: no changed files"
		exit 0
	}
fi
HOOK_DIR="$(git rev-parse --path-format=absolute --git-path hooks)"
ENV_FILE="${HOOK_DIR}/quality-suite.env"
# why: the env file and suite folder are only known at run time
# shellcheck disable=SC1090
if [ -f "$ENV_FILE" ]; then
	set -a
	. "$ENV_FILE"
	set +a
fi
: "${QUALITY_SUITE_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# why: the suite folder is only known at run time
# shellcheck disable=SC1091
. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
# why: the first agent edit after a suite update upgrades the rules file once (like a git hook)
[ "$HOOK" = 1 ] && { (
	. "${QUALITY_SUITE_DIR}/scripts/git-flow-lib.sh"
	qs_suite_stamp_check
) || true; }
# paths relative to the repository root (the container sees the root as /workspace)
# why ask git: on Windows show-toplevel prints C:/x while the shell uses /c/x, so compare nothing
rel=()
for f in "${files[@]}"; do
	case "$f" in /*) ;; *) f="$START/$f" ;; esac
	d="$(dirname "$f")"
	if [ -f "$f" ] && [ "$(cd "$d" && git rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ]; then
		rel+=("$(cd "$d" && git rev-parse --show-prefix)$(basename "$f")")
	else
		echo "[qs-run] skipped (missing or outside $ROOT): $f" >&2
	fi
done
[ "${#rel[@]}" -gt 0 ] || exit 0
files=("${rel[@]}")
cd "$ROOT"

STATE="$(qs_state_dir)"
mkdir -p "$STATE"
LIST="${STATE}/agent-files.lst"
printf '%s\0' "${files[@]}" >"$LIST"
if [ "$ENC" = 1 ]; then
	ENCARGS=()
	[ "$ENCFIX" = 1 ] && ENCARGS=(--fix)
	# why: the encoding check needs no language tools, only the base image
	qs_ensure_image || {
		echo "[quality-suite] cannot build the image; see ${QS_HOME}/install.log" >&2
		exit 1
	}
	ENVF="$(qs_env_file "$ENV_FILE" "${STATE}/agent-docker.env")"
	qs_docker_opts
	qs_git_opts
	rc=0
	docker run "${QS_DOCKER_OPTS[@]}" ${QS_GIT_OPTS[@]+"${QS_GIT_OPTS[@]}"} --env-file "$(qs_hostpath "$ENVF")" \
		-e QS_PERSIST=0 -e QS_STATE=/qs-state -e QS_FILES_FROM=/qs-state/agent-files.lst -e QS_BASE_REV=HEAD \
		-e QUALITY_LOG_FILE=/qs-state/quality-suite.log -e QUALITY_LOG_CONSOLE=ERROR \
		-v "$(qs_hostpath "$ROOT"):/workspace" -v "$(qs_hostpath "$STATE"):/qs-state" -w /workspace \
		"$QUALITY_SUITE_IMAGE" encoding ${ENCARGS[@]+"${ENCARGS[@]}"} || rc=$?
	rm -f "$ENVF"
	exit "$rc"
fi
"${QUALITY_SUITE_DIR}/scripts/ensure-langs.sh" "$QUALITY_SUITE_DIR" "$ENV_FILE" "$QUALITY_SUITE_IMAGE" --from "$LIST" \
	>/dev/null 2>&1 || true
ENVF="$(qs_env_file "$ENV_FILE" "${STATE}/agent-docker.env")"
qs_docker_opts
out="$(docker run "${QS_DOCKER_OPTS[@]}" --env-file "$(qs_hostpath "$ENVF")" \
	-e QUALITY_MODE="$MODE" -e QS_PERSIST=0 -e QS_STATE=/qs-state -e QS_FILES_FROM=/qs-state/agent-files.lst \
	-e QUALITY_LOG_FILE=/qs-state/quality-suite.log -e QUALITY_LOG_CONSOLE=ERROR \
	-v "$(qs_hostpath "$ROOT"):/workspace" -v "$(qs_hostpath "$STATE"):/qs-state" -w /workspace \
	"$QUALITY_SUITE_IMAGE" run 2>&1)" && rc=0 || rc=$?
rm -f "$ENVF"
[ "$rc" -eq 0 ] && exit 0
if [ "$HOOK" = 1 ]; then
	{
		echo "Quality gate findings for ${files[*]} (fix them before going on):"
		printf '%s\n' "$out" | tail -n 60
	} >&2
	exit 2
fi
printf '%s\n' "$out"
exit 1
