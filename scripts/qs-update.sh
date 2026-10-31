#!/usr/bin/env bash
# qs-update.sh - update the suite on this machine as a clean install. Run it from the NEW suite
# folder (or `git actualizar-suite` once setup-global.sh has run there):
#   1. removes leftover containers and every image of the suite (all versions, with their tools)
#   2. builds the base image of this suite folder (no cache: nothing reused from before)
#   3. re-points every installed repository (hooks, aliases) and the global git setup here
# Tools come back on the first commit of each repository that needs them, like a first install.
#   qs-update.sh [--yes] [--lazy] [--langs "java css ..."]
#   qs-update.sh --status        version, image, installed tools, repositories
# --lazy: do not build the base now (the first commit does). --langs: pre-install those now.
set -euo pipefail
QUALITY_SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset QUALITY_SUITE_IMAGE   # why: always this folder's version, never a value from the caller
# shellcheck disable=SC1091
. "$QUALITY_SUITE_DIR/scripts/qs-docker-lib.sh"
trap qs_lock_release EXIT
YES=0 LAZY=0 STATUS=0 LANGS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) YES=1 ;;
    --lazy) LAZY=1 ;;
    --status) STATUS=1 ;;
    --langs) LANGS="${2:?--langs needs a list, e.g. --langs \"java css\"}"; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "[update] unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done
say() { echo "[update] $*"; }
docker info >/dev/null 2>&1 || { echo "[update] Docker is not running; start Docker Desktop and retry." >&2; exit 1; }

repos() {  # installed repositories that still exist
  [ -f "$QS_HOME/repos.list" ] || return 0
  local r
  while IFS= read -r r; do
    [ -n "$r" ] && git -C "$r" rev-parse --git-dir >/dev/null 2>&1 && printf '%s\n' "$r"
  done < "$QS_HOME/repos.list"
  return 0
}
repo_suite() {  # suite folder a repository points to
  local env
  env="$(git -C "$1" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)/quality-suite.env"
  sed -n 's/^QUALITY_SUITE_DIR="\(.*\)"$/\1/p' "$env" 2>/dev/null | head -n1
}

if [ "$STATUS" = 1 ]; then
  echo "Suite folder : $QUALITY_SUITE_DIR (version $QS_VERSION)"
  if docker image inspect "$QUALITY_SUITE_IMAGE" >/dev/null 2>&1; then
    echo "Image        : $QUALITY_SUITE_IMAGE ($(docker image inspect -f '{{.Size}}' "$QUALITY_SUITE_IMAGE" 2>/dev/null \
      | awk '{ printf "%.0f MB", $1 / 1000000 }'), shared by every repository)"
    echo "Tools for    : $(qs_label "$QUALITY_SUITE_IMAGE" qs.langs)"
    echo "Layers       : $(qs_label "$QUALITY_SUITE_IMAGE" qs.layers) (compacted at $QS_MAX_LAYERS)"
  else
    echo "Image        : $QUALITY_SUITE_IMAGE (not built yet: the next commit builds it)"
  fi
  old="$(qs_old_images | tr '\n' ' ')"
  echo "Other images : ${old:-none}${old:+ (remove them: git actualizar-suite)}"
  echo "Containers   : $(docker ps -aq --filter "label=$QS_IMAGE_LABEL" | wc -l | tr -d ' ') left over (each check runs in a throw-away container)"
  echo "Repositories :"
  n=0
  while IFS= read -r r; do
    n=$((n + 1)); s="$(repo_suite "$r")"
    if [ "$s" = "$QUALITY_SUITE_DIR" ]; then echo "  $r"; else echo "  $r  (points to ${s:-?}: run git actualizar-suite)"; fi
  done < <(repos)
  [ "$n" -gt 0 ] || echo "  none registered yet (install.sh / bootstrap.sh registers them)"
  exit 0
fi

say "Clean update to version $QS_VERSION from $QUALITY_SUITE_DIR:"
say "  - remove every code-quality-suite container and image (all versions, with their tools)"
say "  - $([ "$LAZY" = 1 ] && echo "leave the base image to the first commit" || echo "build the base image $QS_BASE_IMAGE (needs network)")"
say "  - re-point the installed repositories and the global git setup to this folder"
say "Tools are downloaded again by the first commit that needs them."
if [ "$YES" != 1 ]; then
  printf '[update] Continue? [y/N] '; read -r ans || ans=""
  case "$ans" in y|Y|s|S|yes|si) ;; *) say "cancelled"; exit 1 ;; esac
fi

qs_lock
# 1. containers: normally none (checks use --rm); a killed commit can leave one behind
ids="$(docker ps -aq --filter "label=$QS_IMAGE_LABEL" | tr '\n' ' ')"
if [ -n "${ids// /}" ]; then
  # shellcheck disable=SC2086
  docker rm -f $ids >/dev/null 2>&1 || true
  say "removed $(wc -w <<<"$ids" | tr -d ' ') container(s)"
fi
# 2. images: every version, tagged or dangling (each tools layer left the previous one behind)
ids="$( { docker image ls -aq --filter "label=$QS_IMAGE_LABEL"; docker image ls -q code-quality-suite; } 2>/dev/null | sort -u | tr '\n' ' ')"
if [ -n "${ids// /}" ]; then
  # shellcheck disable=SC2086
  docker image rm -f $ids >/dev/null 2>&1 || true
  docker image prune -f --filter "label=$QS_IMAGE_LABEL" >/dev/null 2>&1 || true
  say "removed $(wc -w <<<"$ids" | tr -d ' ') image(s)"
fi
# 3. the new base, from scratch
if [ "$LAZY" != 1 ]; then
  say "building $QS_BASE_IMAGE..."
  QS_REBUILD=1 qs_ensure_image
  if [ -n "$LANGS" ]; then
    # shellcheck disable=SC2086
    qs_install_langs _global $LANGS
  fi
fi
qs_unlock

# 4. repositories and global git setup
n=0
while IFS= read -r r; do
  if QS_SKIP_IMAGE=1 "$QUALITY_SUITE_DIR/install.sh" "$r" >/dev/null 2>&1; then n=$((n + 1))
    # why: the AI files carry the suite path and the manual of this version; they are not in git
    if [ -f "$r/AGENTS.md" ]; then
      if ia_out="$(bash "$QUALITY_SUITE_DIR/scripts/ai-init.sh" --actualizar "$r" 2>&1)"; then
        grep -q 'taken out of the index' <<<"$ia_out" \
          && echo "[update] $r: committed AI files taken out of the index (kept on disk); commit it there"
      else echo "[update] WARN: AI files of $r not refreshed (run there: git ia --actualizar)" >&2; fi
    fi
  else echo "[update] WARN: could not re-point $r (run: bash \"$QUALITY_SUITE_DIR/install.sh\" \"$r\")" >&2; fi
done < <(repos)
say "re-pointed $n repositor$([ "$n" = 1 ] && echo y || echo ies)"
if git config --global --get alias.clonar >/dev/null 2>&1; then
  tpl="${CQS_TEMPLATE_DIR:-$HOME/.config/git/cqs-template}"
  on=(); [ -f "$tpl/hooks/post-checkout" ] && on=(--on-clone)
  bash "$QUALITY_SUITE_DIR/git-integration/setup-global.sh" ${on[@]+"${on[@]}"} "$QUALITY_SUITE_DIR" >/dev/null
  say "global git setup (git clonar, git actualizar-suite, clone template) now uses this folder"
fi
say "done. The first commit in each repository reinstalls the tools of its languages (one time)."
say "A repository that is not in the list (git actualizar-suite --status): bash \"$QUALITY_SUITE_DIR/install.sh\" <repo>"
