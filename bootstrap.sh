#!/usr/bin/env bash
# bootstrap.sh - one-shot install from a repo (or by cloning it): clone on URL,
# manage the .gitattributes block, detect project parameters (asked once and
# persisted), build the image and install the hooks. Idempotent.
#   Usage: ./bootstrap.sh <git-url | repo-path> [dest-dir]
#   Also: git clonar <git-url> [dest-dir]   (global alias, see git-integration/)
#   Default clone dest: $QUALITY_WORKSPACE (or CQS_WORKSPACE, or bootstrap.config)/<name>.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/bootstrap.config" ] && . "$SCRIPT_DIR/bootstrap.config"
QUALITY_WORKSPACE="${QUALITY_WORKSPACE:-${CQS_WORKSPACE:-}}"

SRC="${1:?usage: ./bootstrap.sh <git-url|repo-path> [dest-dir]}"
DEST="${2:-}"

case "$SRC" in
http://* | https://* | git@* | ssh://* | file://* | git://*)
	base="$(basename "${SRC%.git}")"
	if [ -n "$DEST" ]; then
		target="$DEST"
	elif [ -n "${QUALITY_WORKSPACE:-}" ]; then
		target="${QUALITY_WORKSPACE%/}/$base"
	else target="$base"; fi
	if [ -d "$target/.git" ]; then
		echo "[bootstrap] '$target' already exists; reusing it."
	else
		echo "[bootstrap] Cloning $SRC -> $target ..."
		git clone "$SRC" "$target"
	fi
	REPO="$(cd "$target" && pwd)"
	;;
*) REPO="$(cd "$SRC" && pwd)" ;;
esac
echo "[bootstrap] Repo: $REPO"

# warn_master: prints one warning when the repository has master and no main. Existing
# repositories are never renamed (the branch model keeps accepting master). Arguments: none
# (reads $REPO). Output: the warning line on stdout, if any. Returns 0.
warn_master() {
	if git -C "$REPO" show-ref --verify --quiet refs/heads/master && ! git -C "$REPO" show-ref --verify --quiet refs/heads/main; then
		echo "[bootstrap] warning: principal branch is master; the suite recommends main (git branch -m master main, then update the remote default branch)"
	fi
	return 0
}
warn_master

HOOK_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)/hooks"
mkdir -p "$HOOK_DIR"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

env_get() { [ -f "$ENV_FILE" ] && sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ENV_FILE" | head -n1 || true; }
env_set() {
	local k="$1" v="$2"
	if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
		sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
	else printf '%s="%s"\n' "$k" "$v" >>"$ENV_FILE"; fi
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
	# why: later lines win in .gitattributes; the managed defaults go FIRST so the project's
	# own rules (e.g. *.sln eol=crlf, *.csv -text) keep precedence.
	local had=0
	[ -f "$ga" ] && grep -qF "$begin" "$ga" && had=1
	{
		printf '%s\n' "$block"
		if [ -f "$ga" ]; then awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$ga"; fi
	} >"$ga.tmp"
	mv "$ga.tmp" "$ga"
	if [ "$had" = 1 ]; then echo "[bootstrap] .gitattributes: block updated"; else echo "[bootstrap] .gitattributes: block added"; fi
}
ensure_gitattributes

"$SCRIPT_DIR/install.sh" "$REPO"

# why: pre-install the tools of the languages already in the repository, so the first commit
# is fast. Versions not found in the project are asked once (they end up in .quality-rules.json).
HOOK_ENV="$(git -C "$REPO" rev-parse --absolute-git-dir)/hooks/quality-suite.env"
IMAGE="${QUALITY_SUITE_IMAGE:-}" # empty = the image of this suite version (shared by all repositories)
FILES=()
while IFS= read -r -d '' f; do if [ -n "$f" ]; then FILES+=("$f"); fi; done < <(git -C "$REPO" ls-files -z)
if [ "${#FILES[@]}" -gt 0 ]; then
	echo "[bootstrap] Detecting languages in ${#FILES[@]} tracked file(s)..."
	(cd "$REPO" && "$SCRIPT_DIR/scripts/ensure-langs.sh" "$SCRIPT_DIR" "$HOOK_ENV" "$IMAGE" -- "${FILES[@]}")
else
	echo "[bootstrap] Empty repository: tools are installed by the first commit that needs them."
fi

echo "[bootstrap] Done. Try:  cd \"$REPO\" && git commit"
