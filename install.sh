#!/usr/bin/env bash
# install.sh - build the base image (tagged by VERSION) and install the hooks into the
# target repo. Language tools are installed later, on demand, by the first commit that
# needs them, into ONE image shared by every repository on this machine. The repo gets thin
# hook wrappers that run the hooks of the suite folder, so updating the suite updates every
# repository (scripts/qs-update.sh). Idempotent via quality-suite.env: QUALITY_SUITE_DIR is
# always refreshed; user parameters (versions, heavy command) are kept.
#   QUALITY_LANGS="java python" ./install.sh   pre-installs those languages now (optional)
#   QS_REPO_FILES=0 ./install.sh               do not create the missing standard repository files
#   Usage: ./install.sh [repo-path]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo latest)"
IMAGE="${QUALITY_SUITE_IMAGE:-code-quality-suite:${VERSION}}"

# QS_SKIP_IMAGE=1: hooks only (qs-update.sh re-points repositories without building anything)
if [ "${QS_SKIP_IMAGE:-0}" != 1 ]; then
  echo "[install] Building ${IMAGE} (base: engine + installer)..."
  # why: the hooks are installed even if the build fails now (Docker stopped, no network): the
  # first commit builds the image, and blocks with the reason if it still cannot
  "${SCRIPT_DIR}/scripts/build-image.sh" "${SCRIPT_DIR}" "${IMAGE}" ${QUALITY_LANGS:-} \
    || echo "[install] WARN: the image could not be built now; the first commit will build it." >&2
fi

TARGET_REPO="${1:-$(pwd)}"
cd "${TARGET_REPO}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "[install] ERROR: '${TARGET_REPO}' is not a git repo." >&2; exit 1; }

# why: core.hooksPath (Husky, corporate setups) and linked worktrees move the hooks directory
if [ -n "$(git config --get core.hooksPath || true)" ] && [ "${QS_FORCE_HOOKS:-0}" != "1" ]; then
  echo "[install] core.hooksPath is set to '$(git config --get core.hooksPath)'; another tool manages hooks." >&2
  echo "          Re-run with QS_FORCE_HOOKS=1 to install there anyway, or call our hooks from that tool." >&2
  exit 1
fi
HOOK_DIR="$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null || echo "$(git rev-parse --absolute-git-dir)/hooks")"
mkdir -p "${HOOK_DIR}"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

# Hooks: ONE copy per machine in $QS_HOME/hooks (default ~/.config/code-quality-suite/hooks; on
# Windows %USERPROFILE%\.config\code-quality-suite\hooks) and, in each repository, symbolic links
# to it. The common hooks run the hook of the suite folder named in the repository's
# quality-suite.env, so updating the suite updates every repository. Where symbolic links cannot
# be created (Windows without Developer Mode) or QS_HOOK_LINKS=0, the repository gets a one-line
# stub that runs the common hook instead. When the suite is missing, the checks block.
QS_HOME="${QS_HOME:-${HOME:-/tmp}/.config/code-quality-suite}"
COMMON="$QS_HOME/hooks"
mkdir -p "$COMMON"
write_common() {  # $1 = hook name, $2 = exit code when the suite is missing
  cat > "$COMMON/$1.tmp.$$" <<EOF
#!/usr/bin/env bash
# code-quality-suite common hook ($1): every repository's .git/hooks/$1 links here. Runs the
# hook of the suite folder named in that repository's quality-suite.env. Written by install.sh.
HOOK_DIR="\$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null || true)"
[ -n "\$HOOK_DIR" ] || HOOK_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
SUITE="\$(sed -n 's/^QUALITY_SUITE_DIR="\\(.*\\)"\$/\\1/p' "\$HOOK_DIR/quality-suite.env" 2>/dev/null | head -n1)"
if [ ! -f "\$SUITE/hooks/$1" ]; then
  echo "[quality-suite] $1: the suite is not at '\${SUITE:-?}' (moved or deleted)." >&2
  echo "                Re-point this repository: bash <suite folder>/install.sh \"\$(git rev-parse --show-toplevel 2>/dev/null)\"" >&2
  exit $2
fi
QS_HOOK_DIR="\$HOOK_DIR" exec bash "\$SUITE/hooks/$1" "\$@"
EOF
  chmod +x "$COMMON/$1.tmp.$$"
  mv -f "$COMMON/$1.tmp.$$" "$COMMON/$1"   # why mv: a hook running right now keeps its old file
}
link_hook() {  # $1 = hook name: .git/hooks/<name> -> $COMMON/<name>
  local target="$COMMON/$1" link="${HOOK_DIR}/$1" made=0
  rm -f "$link"
  if [ "${QS_HOOK_LINKS:-1}" != 0 ]; then
    case "$(uname -s)" in
      # why nativestrict: by default Git Bash's ln -s silently makes a copy, which would not update
      MINGW*|MSYS*|CYGWIN*) MSYS=winsymlinks:nativestrict ln -s "$target" "$link" 2>/dev/null && made=1 ;;
      *) ln -s "$target" "$link" && made=1 ;;
    esac
  fi
  if [ "$made" = 0 ]; then
    printf '#!/usr/bin/env bash\n# code-quality-suite hook stub (no symbolic link here): runs the common hook\nexec "%s" "$@"\n' \
      "$target" > "$link"
    chmod +x "$link"
    HOOK_STUBS=1
  fi
}
HOOK_STUBS=0
for h in pre-commit pre-push prepare-commit-msg commit-msg pre-rebase pre-merge-commit post-checkout; do
  case "$h" in prepare-commit-msg|post-checkout) write_common "$h" 0 ;; *) write_common "$h" 1 ;; esac
  # why: keep a hook that is not ours (e.g. Gerrit's Change-Id commit-msg) instead of overwriting it
  if [ -e "${HOOK_DIR}/$h" ] || [ -L "${HOOK_DIR}/$h" ]; then
    if ! { readlink "${HOOK_DIR}/$h" 2>/dev/null | grep -q 'code-quality-suite'; } \
       && ! grep -q 'code-quality-suite' "${HOOK_DIR}/$h" 2>/dev/null; then
      mv "${HOOK_DIR}/$h" "${HOOK_DIR}/$h.pre-cqs"
      echo "[install] existing $h hook kept as $h.pre-cqs (not chained)" >&2
    fi
  fi
  link_hook "$h"
done

# Repo-local git config + aliases for the branch/merge model (idempotent).
. "${SCRIPT_DIR}/scripts/git-flow-lib.sh"
configure_repo "${SCRIPT_DIR}"

env_set() {
  local k="$1" v="$2"
  if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
    sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"; fi
}

touch "$ENV_FILE"
# Derived keys: always current.
env_set QUALITY_SUITE_DIR   "$SCRIPT_DIR"
# why: the image name follows the suite VERSION at run time (one shared image per version);
# store it only when the caller asked for a custom image explicitly
if [ -n "${QUALITY_SUITE_IMAGE:-}" ]; then env_set QUALITY_SUITE_IMAGE "$IMAGE"
else sed -i.bak '/^QUALITY_SUITE_IMAGE=/d' "$ENV_FILE" && rm -f "$ENV_FILE.bak"; fi
sed -i.bak '/^QUALITY_LANGS=/d' "$ENV_FILE" && rm -f "$ENV_FILE.bak"   # why: v1 key; the image label tracks it now
# why: versions are pinned in .quality-rules.json; legacy keys here (PMD_JAVA_VERSION...) still seed it.
grep -q "QUALITY_HEAVY_CMD" "$ENV_FILE"     || printf '# QUALITY_HEAVY_CMD="mvn -B verify"\n' >> "$ENV_FILE"
# why: commit and branch policies live in .quality-rules.json ("commit", "branches") since 2.1
sed -i.bak -E '/^COMMIT_(SUBJECT_MAX|TYPES)=/d' "$ENV_FILE" && rm -f "$ENV_FILE.bak"

# why: the rules file is personal to each clone; ignore it locally without touching .gitignore.
EXCL="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$EXCL")"
grep -qx '/.quality-rules.json' "$EXCL" 2>/dev/null || echo '/.quality-rules.json' >> "$EXCL"
mkdir -p "$(git rev-parse --absolute-git-dir)/quality-suite"

# why: scripts/qs-update.sh re-points every repository installed on this machine
touch "$QS_HOME/repos.list"
REPO_TOP="$(cd "$(git rev-parse --show-toplevel)" && pwd)"
grep -qxF "$REPO_TOP" "$QS_HOME/repos.list" || printf '%s\n' "$REPO_TOP" >> "$QS_HOME/repos.list"

echo "[install] Hooks: pre-commit, pre-push, prepare-commit-msg, commit-msg, pre-rebase, pre-merge-commit,"
echo "          post-checkout -> $([ "$HOOK_STUBS" = 1 ] && echo "stubs running" || echo "symbolic links to") ${COMMON}"
echo "[install] Rules file: .quality-rules.json (created on the first commit; schema: ${SCRIPT_DIR}/schema/)"
echo "[install] Branch commands (git aliases): git np | nr | convertir-padre | subir | integra | arbol | estructura (es) | changelog | release | publicar"
echo "[install] Other aliases: git encoding [--fix] | git repo-files"
echo "[install] Config: ${ENV_FILE}"
echo "[install] Image:  ${IMAGE} (one image per suite version, shared by every repository)"

# Standard repository files (README, CHANGELOG, VERSION, CONTRIBUTING... DEVELOPMENT): the missing
# ones are created from the git history and pom.xml, never overwritten, and left for you to review
# and commit. Not during updates (QS_SKIP_IMAGE=1) or with QS_REPO_FILES=0.
if [ "${QS_SKIP_IMAGE:-0}" != 1 ] && [ "${QS_REPO_FILES:-1}" != 0 ]; then
  echo "[install] Repository files (missing ones only; review and commit them):"
  if out="$(bash "${SCRIPT_DIR}/scripts/git-rama.sh" repo-files 2>&1)"; then
    printf '%s\n' "$out" | grep -v ' exists: ' || echo "  (all present)"
  else
    echo "[install] WARN: repository files not created now ($(printf '%s' "$out" | tail -n1)); later: git repo-files" >&2
  fi
fi
