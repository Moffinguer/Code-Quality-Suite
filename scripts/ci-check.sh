#!/usr/bin/env bash
# =============================================================================
# ci-check.sh — ejecuta la suite en modo CHECK (no modifica) sobre los ficheros
# cambiados respecto a una base. Pensado para CI/CD.
#   Uso:  ci-check.sh [base_ref]        (por defecto origin/main)
#   ALL=1 ci-check.sh                   -> escanea TODO el repo (nocturno)
# =============================================================================
set -euo pipefail

BASE="${1:-origin/main}"
IMAGE="${QUALITY_SUITE_IMAGE:-code-quality-suite:latest}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

FILES=()
if [ "${ALL:-0}" = "1" ]; then
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(git -C "$REPO_ROOT" ls-files)
else
  mb="$(git merge-base HEAD "$BASE" 2>/dev/null || echo "$BASE")"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$REPO_ROOT/$f" ] && FILES+=("$f")
  done < <(git -C "$REPO_ROOT" diff --name-only --diff-filter=ACM "${mb}...HEAD")
fi

if [ "${#FILES[@]}" -eq 0 ]; then echo "[ci] nada que verificar"; exit 0; fi
echo "[ci] verificando ${#FILES[@]} fichero(s) en modo check..."

docker run --rm --network none --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  -e HOME=/tmp -e QUALITY_MODE=check -e PMD_JAVA_VERSION="${PMD_JAVA_VERSION:-21}" \
  -v "${REPO_ROOT}:/workspace:ro" -w /workspace \
  "${IMAGE}" "${FILES[@]}"
