#!/usr/bin/env bash
# =============================================================================
# install.sh — construye la imagen (tag por versión) e instala pre-commit y
# pre-push en el repo objetivo. Idempotente con quality-suite.env:
#   - claves derivadas (DIR, IMAGE) se actualizan siempre
#   - parámetros de usuario (PMD_JAVA_VERSION, ...) se conservan si ya existen
#   Uso: ./install.sh [ruta-al-repo]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo latest)"
IMAGE="${QUALITY_SUITE_IMAGE:-code-quality-suite:${VERSION}}"

echo "[install] Construyendo ${IMAGE}..."
docker build -t "${IMAGE}" "${SCRIPT_DIR}"

TARGET_REPO="${1:-$(pwd)}"
cd "${TARGET_REPO}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "[install] ERROR: '${TARGET_REPO}' no es un repo git." >&2; exit 1; }

HOOK_DIR="$(git rev-parse --absolute-git-dir)/hooks"
mkdir -p "${HOOK_DIR}"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

for h in pre-commit pre-push prepare-commit-msg commit-msg; do
  cp "${SCRIPT_DIR}/hooks/$h" "${HOOK_DIR}/$h"
  chmod +x "${HOOK_DIR}/$h"
done

env_set() { # KEY VALUE
  local k="$1" v="$2"
  if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
    sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"; fi
}

touch "$ENV_FILE"
# Derivadas: siempre al día.
env_set QUALITY_SUITE_DIR  "$SCRIPT_DIR"
env_set QUALITY_SUITE_IMAGE "$IMAGE"
# Parámetros de usuario: solo por defecto si aún no existen.
grep -q "^PMD_JAVA_VERSION=" "$ENV_FILE" || env_set PMD_JAVA_VERSION "21"
grep -q "QUALITY_HEAVY_CMD" "$ENV_FILE"  || printf '# QUALITY_HEAVY_CMD="mvn -B verify"\n' >> "$ENV_FILE"
grep -q "^COMMIT_SUBJECT_MAX=" "$ENV_FILE" || env_set COMMIT_SUBJECT_MAX "50"
grep -q "^COMMIT_TYPES=" "$ENV_FILE"       || env_set COMMIT_TYPES "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

echo "[install] Hooks instalados: pre-commit, pre-push, prepare-commit-msg, commit-msg"
echo "[install] Config:  ${ENV_FILE}"
echo "[install] Imagen:  ${IMAGE}"
