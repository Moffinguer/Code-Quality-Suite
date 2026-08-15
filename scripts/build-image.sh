#!/usr/bin/env bash
# build-image.sh - build the image with only the given language groups.
#   build-image.sh <suite_dir> <image_tag> [lang1 lang2 ...]
# No languages means a minimal base image.
set -euo pipefail
SUITE_DIR="$1"; IMAGE="$2"; shift 2
langs=" $* "
has(){ case "$langs" in *" $1 "*) return 0;; *) return 1;; esac; }

args=()
for g in java web markdown xml docker perl sql python cpp shell; do
  if has "$g"; then
    G="$(echo "$g" | tr '[:lower:]' '[:upper:]')"
    args+=(--build-arg "ENABLE_${G}=1")
  fi
done
# why: Node is shared by web and markdown; the Python venv by python and sql.
if has web || has markdown; then args+=(--build-arg ENABLE_NODE=1); fi
if has python || has sql;    then args+=(--build-arg ENABLE_PYVENV=1); fi

echo "[build] Image ${IMAGE} with languages: ${*:-(none, minimal base)}"
docker build "${args[@]}" -t "${IMAGE}" "${SUITE_DIR}"
