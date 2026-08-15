#!/usr/bin/env bash
# install.sh - build the image (tagged by VERSION) and install the hooks into the
# target repo. Idempotent via quality-suite.env: derived keys (DIR, IMAGE, LANGS)
# are always refreshed; user parameters are kept if already present.
#   Usage: ./install.sh [repo-path]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo latest)"
IMAGE="${QUALITY_SUITE_IMAGE:-code-quality-suite:${VERSION}}"

echo "[install] Building ${IMAGE}..."
"${SCRIPT_DIR}/scripts/build-image.sh" "${SCRIPT_DIR}" "${IMAGE}" ${QUALITY_LANGS:-}

TARGET_REPO="${1:-$(pwd)}"
cd "${TARGET_REPO}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "[install] ERROR: '${TARGET_REPO}' is not a git repo." >&2; exit 1; }

HOOK_DIR="$(git rev-parse --absolute-git-dir)/hooks"
mkdir -p "${HOOK_DIR}"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

for h in pre-commit pre-push prepare-commit-msg commit-msg; do
  cp "${SCRIPT_DIR}/hooks/$h" "${HOOK_DIR}/$h"
  chmod +x "${HOOK_DIR}/$h"
done

env_set() {
  local k="$1" v="$2"
  if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
    sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"; fi
}

touch "$ENV_FILE"
# Derived keys: always current.
env_set QUALITY_SUITE_DIR   "$SCRIPT_DIR"
env_set QUALITY_SUITE_IMAGE "$IMAGE"
env_set QUALITY_LANGS "${QUALITY_LANGS:-}"
# why: PMD_JAVA_VERSION is set lazily on first Java file; hooks fall back to 21.
grep -q "QUALITY_HEAVY_CMD" "$ENV_FILE"     || printf '# QUALITY_HEAVY_CMD="mvn -B verify"\n' >> "$ENV_FILE"
grep -q "^COMMIT_SUBJECT_MAX=" "$ENV_FILE"  || env_set COMMIT_SUBJECT_MAX "50"
grep -q "^COMMIT_TYPES=" "$ENV_FILE"        || env_set COMMIT_TYPES "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

echo "[install] Hooks installed: pre-commit, pre-push, prepare-commit-msg, commit-msg"
echo "[install] Config: ${ENV_FILE}"
echo "[install] Image:  ${IMAGE}"
