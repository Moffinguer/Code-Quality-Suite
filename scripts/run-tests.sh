#!/usr/bin/env bash
# run-tests.sh <repo_root> - run project tests before a delicate op (push).
# Order of precedence:
#   1) "tests" in .quality-rules.json (exported by the engine to .git/quality-suite/tests.txt)
#   2) explicit .quality-tests file at the repo root (one command per line)
#   3) autodetect common packagers ("tests.autodetect": true, or QUALITY_TESTS_AUTODETECT=1)
#   4) nothing -> skip (no tests defined)
# Runs on the host (needs the project toolchain). Any failure blocks the push.
set -uo pipefail
REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
SUITE_DIR="${QUALITY_SUITE_DIR:-}"
if [ -f "$SUITE_DIR/log-lib.sh" ] && . "$SUITE_DIR/log-lib.sh"; then
	:
else
	qs_log() { :; }
	qs_result() { :; }
fi
cd "$REPO" || exit 1
rc=0
# run_cmd COMMAND: run one test command on the host (stdin closed) and log SUCCESS or ERROR.
# Arguments: $1 command line (run through eval). Returns: 0; a failure sets rc to 1 and the loop
# goes on. Errors: none beyond that.
run_cmd() {
	qs_log INFO tests "run: $1"
	echo "[quality-suite] tests: $1"
	# why: a command that reads stdin must not swallow the rest of the command list
	if (eval "$1") </dev/null; then qs_result tests "$1" test SUCCESS; else
		qs_result tests "$1" test ERROR
		rc=1
	fi
}

CFG=""
EXPORTED="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null)/quality-suite/tests.txt"
if [ -s "$EXPORTED" ] && grep -qv '^@autodetect$' "$EXPORTED"; then CFG="$EXPORTED"; fi
[ -s "$EXPORTED" ] && grep -qx '@autodetect' "$EXPORTED" && QUALITY_TESTS_AUTODETECT=1
if [ -z "$CFG" ]; then
	for c in .quality-tests quality-tests.txt; do [ -f "$REPO/$c" ] && {
		CFG="$REPO/$c"
		break
	}; done
fi

if [ -n "$CFG" ]; then
	qs_log INFO tests "using $CFG"
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in \#* | [[:space:]]\#*) continue ;; esac
		line="${line%%[[:space:]]#*}" # why: only " #" starts a comment (Foo#method stays intact)
		line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
		[ -z "$line" ] || [ "$line" = "@autodetect" ] && continue
		run_cmd "$line"
	done <"$CFG"
elif [ "${QUALITY_TESTS_AUTODETECT:-0}" = "1" ]; then
	if [ -f pom.xml ]; then
		run_cmd "mvn -B test"
	elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
		run_cmd "./gradlew test"
	elif [ -f package.json ] && grep -q '"test"' package.json; then
		run_cmd "npm test --silent"
	elif [ -f Cargo.toml ]; then
		run_cmd "cargo test"
	elif [ -f go.mod ]; then
		run_cmd "go test ./..."
	elif [ -f Makefile ] && grep -qE '^test:' Makefile; then
		run_cmd "make test"
	else qs_log INFO tests "autodetect on but no known packager found"; fi
else
	qs_log INFO tests "no .quality-tests and autodetect off; skipping"
	echo "[quality-suite] tests: none defined (.quality-tests absent); skipping"
fi
exit $rc
