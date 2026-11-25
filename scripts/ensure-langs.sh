#!/usr/bin/env bash
# ensure-langs.sh - on-demand install. Detects the languages of the files with the engine
# (extension, name, shebang, modeline, content probes, file(1)); if the image lacks their
# tools, adds an image layer with them. The first time a language with a version knob
# appears in the repository and the project does not reveal its version, asks once on the
# terminal and stores the answer (the engine then pins it in .quality-rules.json).
#   ensure-langs.sh <suite_dir> <env_file> <image> --from <nul-separated-list>
#   ensure-langs.sh <suite_dir> <env_file> <image> -- <files...>
# QS_RETRY_FAILED=1 retries tools whose install failed; QS_NO_PROMPT=1 never asks.
set -euo pipefail
QUALITY_SUITE_DIR="$1"
ENV_FILE="$2"
QUALITY_SUITE_IMAGE="$3"
shift 3
. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
trap qs_lock_release EXIT

STATE="$(qs_state_dir)"
mkdir -p "$STATE"
LIST="${STATE}/detect.lst"
if [ "${1:-}" = "--from" ]; then
	[ "$2" = "$LIST" ] || cp "$2" "$LIST"
else
	[ "${1:-}" = "--" ] && shift
	if [ "$#" -gt 0 ]; then printf '%s\0' "$@" >"$LIST"; else : >"$LIST"; fi
fi
[ -s "$LIST" ] || exit 0

# env_get NAME: print the value of NAME in the environment file (nothing when absent).
# Arguments: $1 variable name. Returns: 0. Errors: none; a missing file gives an empty value.
env_get() { [ -f "$ENV_FILE" ] && sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ENV_FILE" | head -n1 || true; }
# env_set NAME VALUE: set NAME="VALUE" in the environment file, replacing its line or appending one.
# Arguments: $1 variable name; $2 value. Returns: 0. Errors: none.
env_set() { if [ -f "$ENV_FILE" ] && grep -q "^$1=" "$ENV_FILE"; then sed -i.bak "s|^$1=.*|$1=\"$2\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"; else printf '%s="%s"\n' "$1" "$2" >>"$ENV_FILE"; fi; }

qs_ensure_image
detected="$(qs_engine_query langs "$LIST" || true)"
want="_global $detected"
have=" $(qs_label "$QUALITY_SUITE_IMAGE" qs.langs) "
missing=""
for t in $want; do
	case "$have" in *" $t "*) ;; *) case " $missing " in *" $t "*) ;; *) missing="$missing $t" ;; esac ;; esac
done
missing="$(echo "$missing" | xargs || true)"
[ "${QS_RETRY_FAILED:-0}" = "1" ] && missing="$(echo "$have $missing" | xargs || true)"

# Languages not yet in the rules file (first appearance in this repository).
rules="$(qs_repo_root)/.quality-rules.json"
new_langs=""
for t in $detected; do
	case "$t" in tool:*) continue ;; esac
	l="${t%%/*}"
	grep -q "\"$l\": {" "$rules" 2>/dev/null || new_langs="$new_langs $l"
done

# First appearance: ask for versions the project does not reveal (legacy behaviour of v1).
if [ -n "$new_langs" ] && [ -t 2 ] && [ "${QS_NO_PROMPT:-0}" != "1" ] && { exec 3</dev/tty; } 2>/dev/null; then
	while IFS=$'\t' read -r lang var def label; do
		{ [ -n "$var" ] && [ "$var" != "-" ]; } || continue
		[ -n "$(env_get "$var")" ] && continue
		[ "$def" = "-" ] && def=""
		printf '[quality-suite] First %s file. %s [%s]: ' "$lang" "$label" "$def" >&2
		ans=""
		read -r ans <&3 || ans=""
		if [ -n "${ans:-$def}" ]; then env_set "$var" "${ans:-$def}"; fi
	done < <(qs_engine_query ask "$LIST" || true)
	exec 3<&-
fi

# shellcheck disable=SC2086 # why: missing is a space separated list of tools; one argument per tool
if [ -n "$missing" ]; then qs_install_langs $missing; fi
exit 0
