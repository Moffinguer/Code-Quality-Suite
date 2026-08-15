#!/usr/bin/env bash
# bootstrap.sh - one-shot install from a repo (or by cloning it): clone on URL,
# manage the .gitattributes block, detect project parameters (asked once and
# persisted), build the image and install the hooks. Idempotent.
#   Usage: ./bootstrap.sh <git-url | repo-path> [dest-dir]
#   Default clone dest: $QUALITY_WORKSPACE/<name> when set.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC="${1:?usage: ./bootstrap.sh <git-url|repo-path> [dest-dir]}"
DEST="${2:-}"

case "$SRC" in
  http://*|https://*|git@*|ssh://*)
    base="$(basename "${SRC%.git}")"
    if [ -n "$DEST" ]; then target="$DEST"
    elif [ -n "${QUALITY_WORKSPACE:-}" ]; then target="${QUALITY_WORKSPACE%/}/$base"
    else target="$base"; fi
    if [ -d "$target/.git" ]; then echo "[bootstrap] '$target' already exists; reusing it.";
    else echo "[bootstrap] Cloning $SRC -> $target ..."; git clone "$SRC" "$target"; fi
    REPO="$(cd "$target" && pwd)" ;;
  *) REPO="$(cd "$SRC" && pwd)" ;;
esac
echo "[bootstrap] Repo: $REPO"

HOOK_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)/hooks"
mkdir -p "$HOOK_DIR"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

env_get() { [ -f "$ENV_FILE" ] && sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ENV_FILE" | head -n1 || true; }
env_set() {
  local k="$1" v="$2"
  if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
    sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"; fi
}

# Managed block in .gitattributes (create or replace).
ensure_gitattributes() {
  local ga="$REPO/.gitattributes"
  local begin="# >>> code-quality-suite (managed) >>>"
  local end="# <<< code-quality-suite <<<"
  local block
  block="$begin
* text=auto eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
$end"
  if [ -f "$ga" ] && grep -qF "$begin" "$ga"; then
    awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$ga" > "$ga.tmp"
    printf '%s\n' "$block" >> "$ga.tmp"; mv "$ga.tmp" "$ga"
    echo "[bootstrap] .gitattributes: block updated"
  else
    [ -f "$ga" ] && printf '\n' >> "$ga"
    printf '%s\n' "$block" >> "$ga"
    echo "[bootstrap] .gitattributes: block added"
  fi
}
ensure_gitattributes

# why: the Java version drives PMD's language level; read it from pom.xml if present.
detect_java_version() {
  local pom="$REPO/pom.xml" v=""
  if [ -f "$pom" ]; then
    v="$(sed -n 's:.*<java.version>\([0-9][0-9.]*\)</java.version>.*:\1:p' "$pom" | head -n1)"
    [ -z "$v" ] && v="$(sed -n 's:.*<maven.compiler.release>\([0-9][0-9.]*\)</maven.compiler.release>.*:\1:p' "$pom" | head -n1)"
    [ -z "$v" ] && v="$(sed -n 's:.*<maven.compiler.source>\([0-9][0-9.]*\)</maven.compiler.source>.*:\1:p' "$pom" | head -n1)"
  fi
  printf '%s' "$v"
}

LANGS="$("$SCRIPT_DIR/scripts/detect-languages.sh" "$REPO")"
if [ -z "$LANGS" ]; then
  echo "[bootstrap] Empty project or no known languages: minimal base image (no tools)."
else
  echo "[bootstrap] Detected languages: $LANGS"
fi

# why: ask the Java version only when the project already has Java and it is unset.
if echo " $LANGS " | grep -q " java " && [ -z "$(env_get PMD_JAVA_VERSION)" ]; then
  JV="$(detect_java_version)"
  if [ -n "$JV" ]; then
    echo "[bootstrap] Java detected in pom.xml: $JV"
  else
    printf "[bootstrap] Java project. Java version (e.g. 17, 21): "
    read -r JV < /dev/tty 2>/dev/null || JV=""
    [ -z "$JV" ] && JV="21"
  fi
  env_set PMD_JAVA_VERSION "$JV"
fi

export QUALITY_LANGS="$LANGS"
"$SCRIPT_DIR/install.sh" "$REPO"

echo "[bootstrap] Done. Try:  cd \"$REPO\" && git commit"
