#!/usr/bin/env bash
# build-image.sh - build the base image and, optionally, a layer with the given languages.
#   build-image.sh <suite_dir> <image> [lang ...]      e.g. java python yaml/github-workflow
# No languages = base only (tools are then installed on demand by the hooks).
# QS_REBUILD=1 rebuilds the base from scratch (after editing the Dockerfile or the engine).
#   build-image.sh --pin <suite_dir>   write base-image.lock with the digest of ubuntu:24.04 now
# QS_APT_SNAPSHOT=<YYYYMMDDTHHMMSSZ|off> overrides the apt snapshot date of the Dockerfile.
set -euo pipefail
if [ "${1:-}" = "--pin" ]; then
  docker pull -q ubuntu:24.04 >/dev/null
  docker image inspect --format '{{index .RepoDigests 0}}' ubuntu:24.04 > "${2:-.}/base-image.lock"
  echo "[build] pinned: $(cat "${2:-.}/base-image.lock") (rebuild with QS_REBUILD=1)"; exit 0
fi
QUALITY_SUITE_DIR="$1"; QUALITY_SUITE_IMAGE="$2"; shift 2
. "${QUALITY_SUITE_DIR}/scripts/qs-docker-lib.sh"
trap qs_lock_release EXIT
if [ "${QS_REBUILD:-0}" = "1" ]; then
  docker image rm -f "$QS_BASE_IMAGE" "$QUALITY_SUITE_IMAGE" >/dev/null 2>&1 || true
fi
qs_ensure_image
[ "$#" -gt 0 ] && qs_install_langs _global "$@"
echo "[build] ${QUALITY_SUITE_IMAGE} ready (tools for: $(qs_label "$QUALITY_SUITE_IMAGE" qs.langs))"
