#!/usr/bin/env bash
# ensure-langs.sh - lazy install. If <files> introduce a language not yet in
# QUALITY_LANGS, rebuild the image adding it. On the first Java file with no
# PMD_JAVA_VERSION, ask for it (or read it from pom.xml). Idempotent.
#   ensure-langs.sh <suite_dir> <env_file> <image> -- <files...>
set -euo pipefail
SUITE_DIR="$1"; ENV_FILE="$2"; IMAGE="$3"; shift 3
[ "${1:-}" = "--" ] && shift
[ "$#" -eq 0 ] && exit 0

env_get(){ [ -f "$ENV_FILE" ] && sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ENV_FILE" | head -n1 || true; }
env_set(){ if [ -f "$ENV_FILE" ] && grep -q "^$1=" "$ENV_FILE"; then sed -i.bak "s|^$1=.*|$1=\"$2\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"; else printf '%s="%s"\n' "$1" "$2" >> "$ENV_FILE"; fi; }

cur="$(env_get QUALITY_LANGS)"
new="$("$SUITE_DIR/scripts/detect-languages.sh" --files "$@")"

merged="$cur"; changed=0
for l in $new; do
  case " $merged " in *" $l "*) ;; *) merged="$merged $l"; changed=1;; esac
done
merged="$(echo "$merged" | xargs || true)"
[ "$changed" = "0" ] && exit 0

# why: prompt for the Java version only the first time Java shows up, not before.
if echo " $new " | grep -q ' java ' && [ -z "$(env_get PMD_JAVA_VERSION)" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
  jv=""
  [ -f "$root/pom.xml" ] && jv="$(sed -n 's:.*<java.version>\([0-9][0-9.]*\)</java.version>.*:\1:p' "$root/pom.xml" | head -n1)"
  if [ -z "$jv" ]; then
    printf "[quality-suite] First Java file detected. Project Java version (e.g. 17, 21): " >&2
    read -r jv < /dev/tty 2>/dev/null || jv=""
    [ -z "$jv" ] && jv="21"
  fi
  env_set PMD_JAVA_VERSION "$jv"
fi

env_set QUALITY_LANGS "$merged"
echo "[quality-suite] New language '$new'. Rebuilding image (languages: $merged)..." >&2
"$SUITE_DIR/scripts/build-image.sh" "$SUITE_DIR" "$IMAGE" $merged
