#!/usr/bin/env bash
# qs-docker-lib.sh - shared host helpers for the hooks and scripts (sourced, not executed).
# Needs: QUALITY_SUITE_DIR, QUALITY_SUITE_IMAGE (defaults below), git, docker.
# Windows (Git Bash): MSYS path conversion is off for docker calls, so every host path given
# to docker.exe goes through qs_hostpath (C:/... form). File lists travel in NUL-separated
# files, never on the command line (Windows caps it at 32K characters).

QS_VERSION="$(tr -d '[:space:]' < "${QUALITY_SUITE_DIR}/VERSION" 2>/dev/null || echo latest)"
# why: one image per suite version, shared by every repository on this machine; the tag follows
# the suite folder at run time, so updating the suite moves every repository to the new image.
# A tag frozen by an older install.sh (code-quality-suite:<other version>) is ignored.
case "${QUALITY_SUITE_IMAGE:-}" in
  code-quality-suite:[0-9]*) [ "${QUALITY_SUITE_IMAGE#*:}" = "$QS_VERSION" ] || QUALITY_SUITE_IMAGE="" ;;
esac
: "${QUALITY_SUITE_IMAGE:=code-quality-suite:${QS_VERSION}}"
QS_BASE_IMAGE="${QUALITY_SUITE_IMAGE%:*}:base-${QS_VERSION}"
QS_MAX_LAYERS="${QS_MAX_LAYERS:-40}"
QS_IMAGE_LABEL="org.opencontainers.image.title=code-quality-suite"   # set by the Dockerfile
# Network of the image builds (tool downloads). Behind a corporate proxy, set the proxy in Docker
# Desktop (Settings > Resources > Proxies) or ~/.docker/config.json; QS_BUILD_NETWORK=host only
# when the proxy listens on this machine's localhost.
QS_BUILD_OPTS=(); if [ -n "${QS_BUILD_NETWORK:-}" ]; then QS_BUILD_OPTS=(--network "$QS_BUILD_NETWORK"); fi
# per-user state shared by all repositories: install lock, list of installed repositories
QS_HOME="${QS_HOME:-${HOME:-/tmp}/.config/code-quality-suite}"

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 ;; esac

qs_hostpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
qs_repo_root() { git rev-parse --show-toplevel; }
qs_state_dir() { echo "$(git rev-parse --absolute-git-dir)/quality-suite"; }
qs_label() { docker image inspect -f "{{ index .Config.Labels \"$2\" }}" "$1" 2>/dev/null || true; }

# Read a NUL-separated list file into the QS_FILES array (names with spaces/accents are safe).
qs_read_list() {
  QS_FILES=()
  local f
  while IFS= read -r -d '' f; do if [ -n "$f" ]; then QS_FILES+=("$f"); fi; done < "$1"
}

# Machine-wide lock around image changes: two repositories committing at the same time must not
# build layers from the same parent (the last tag would drop the other's tools). mkdir is atomic
# everywhere (Git Bash included). Re-entrant; a lock whose process is gone, or older than
# QS_LOCK_STALE seconds (default 3600), is taken over. Scripts call qs_lock_release on EXIT.
QS_LOCK_DEPTH=0
qs_lock() {
  local d="$QS_HOME/image.lock" pid since waited=0
  QS_LOCK_DEPTH=$((QS_LOCK_DEPTH + 1))
  [ "$QS_LOCK_DEPTH" -gt 1 ] && return 0
  mkdir -p "$QS_HOME"
  until mkdir "$d" 2>/dev/null; do
    pid="$(cat "$d/pid" 2>/dev/null || true)"; since="$(cat "$d/since" 2>/dev/null || date +%s)"
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ $(( $(date +%s) - since )) -gt "${QS_LOCK_STALE:-3600}" ]; then
      rm -rf "$d"; continue
    fi
    [ "$waited" = 0 ] && echo "[quality-suite] Another repository is changing the image (pid ${pid:-?}); waiting..." >&2
    waited=1; sleep 2
  done
  echo "$$" > "$d/pid"; date +%s > "$d/since"
}
qs_unlock() {
  [ "$QS_LOCK_DEPTH" -gt 0 ] || return 0
  QS_LOCK_DEPTH=$((QS_LOCK_DEPTH - 1))
  [ "$QS_LOCK_DEPTH" -gt 0 ] || rm -rf "$QS_HOME/image.lock"
}
qs_lock_release() { [ "$QS_LOCK_DEPTH" -gt 0 ] && rm -rf "$QS_HOME/image.lock"; QS_LOCK_DEPTH=0; }

# Suite images of other versions still on disk (after an update), one per line.
qs_old_images() {
  docker image ls --filter "label=$QS_IMAGE_LABEL" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
    | grep -v ':<none>$' | grep -vxF -e "$QUALITY_SUITE_IMAGE" -e "$QS_BASE_IMAGE" || true
}

# Build the base image (engine + installer only) when missing or from another suite version.
qs_build_base() {
  local nc=()
  [ "${QS_REBUILD:-0}" = "1" ] && nc=(--no-cache)
  if docker image inspect "$QS_BASE_IMAGE" >/dev/null 2>&1; then return 0; fi
  # why: reproducible base: the Ubuntu digest in base-image.lock and a fixed apt snapshot date
  local args=() lock="${QUALITY_SUITE_DIR}/base-image.lock"
  [ -s "$lock" ] && args+=(--build-arg "UBUNTU_IMAGE=$(tr -d '[:space:]' < "$lock")")
  [ -n "${QS_APT_SNAPSHOT:-}" ] && args+=(--build-arg "QS_APT_SNAPSHOT=${QS_APT_SNAPSHOT}")
  echo "[quality-suite] Building base image ${QS_BASE_IMAGE}..." >&2
  docker build ${nc[@]+"${nc[@]}"} ${QS_BUILD_OPTS[@]+"${QS_BUILD_OPTS[@]}"} ${args[@]+"${args[@]}"} -q -t "$QS_BASE_IMAGE" "$(qs_hostpath "$QUALITY_SUITE_DIR")" >/dev/null
  local old; old="$(qs_old_images | tr '\n' ' ')"
  [ -z "$old" ] || echo "[quality-suite] Images of other suite versions are still on disk: ${old}(free the space: git actualizar-suite)" >&2
}

# The image of this suite version exists (base + tags); tools are added by qs_install_langs.
qs_ensure_image() {
  docker image inspect "$QUALITY_SUITE_IMAGE" >/dev/null 2>&1 && return 0
  qs_lock
  if ! docker image inspect "$QUALITY_SUITE_IMAGE" >/dev/null 2>&1; then
    qs_build_base || { qs_unlock; return 1; }
    docker image inspect "$QUALITY_SUITE_IMAGE" >/dev/null 2>&1 || docker tag "$QS_BASE_IMAGE" "$QUALITY_SUITE_IMAGE"
  fi
  qs_unlock
}

# Read-only view of the repository's object store, for the previous version of each file.
# why: the encoding check tells new damage from damage already committed with 'git cat-file';
# a worktree's .git and the tree exported by pre-push are not usable inside the container
qs_git_opts() {
  local gd
  QS_GIT_OPTS=()
  gd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  QS_GIT_OPTS=(-v "$(qs_hostpath "$gd"):/qs-git:ro" -e QS_GIT_DIR=/qs-git)
}

# Common hardening for every analysis run: no network, read-only root, no capabilities.
qs_docker_opts() {
  QS_DOCKER_OPTS=(--rm --network none --read-only --tmpfs /tmp:rw,exec,size=2g
    --cap-drop ALL --security-opt no-new-privileges -e HOME=/tmp)
  if [ "$(uname -s)" = "Linux" ]; then
    # why: rootless Docker/Podman maps --user to a sub-uid that cannot write the bind mount
    if [ -z "${QS_ROOTLESS:-}" ]; then
      QS_ROOTLESS=0
      docker info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless && QS_ROOTLESS=1
      export QS_ROOTLESS
    fi
    [ "$QS_ROOTLESS" = "1" ] || QS_DOCKER_OPTS+=(--user "$(id -u):$(id -g)")
  fi
}

# Env file for docker: version knobs and log settings from quality-suite.env (quotes stripped).
qs_env_file() {
  # why: on Windows the file must have a path docker.exe understands, so callers pass one
  # inside the repository's git dir (mktemp would give an MSYS /tmp path).
  local src="$1" out="${2:-$(mktemp)}"
  : > "$out"
  if [ -f "$src" ]; then
    grep -E '^(QUALITY_LEVEL|QUALITY_LOG_LEVEL|QUALITY_LOG_FORMAT|QUALITY_LOG_CONSOLE|[A-Z0-9_]*(VERSION|DIALECT|EDITION|_STD))=' "$src" \
      | grep -v '^QUALITY_SUITE' | sed -E 's/^([A-Z0-9_]+)="(.*)"$/\1=\2/' >> "$out" || true
  fi
  local v
  for v in QUALITY_LEVEL QUALITY_LOG_LEVEL QUALITY_LOG_FORMAT QUALITY_LOG_CONSOLE QS_NO_PROMPT; do
    [ -n "${!v:-}" ] && printf '%s=%s\n' "$v" "${!v}" >> "$out"
  done
  echo "$out"
}

# Run an engine command that edits files of a folder: version files, release notes, repository
# files. The folder is /workspace (writable); the git objects are mounted read-only.
#   qs_engine_tool <folder> <qs.py command> [arguments...]
qs_engine_tool() {
  local dir="$1"; shift
  qs_ensure_image >&2 || return 1
  qs_docker_opts; qs_git_opts
  docker run "${QS_DOCKER_OPTS[@]}" ${QS_GIT_OPTS[@]+"${QS_GIT_OPTS[@]}"} -e QS_PERSIST=0 \
    -e QS_REPO_NAME="$(basename "$(qs_repo_root)")" -e QUALITY_LOG_CONSOLE=ERROR \
    -v "$(qs_hostpath "$dir"):/workspace" -w /workspace -e QS_ROOT=/workspace "$QUALITY_SUITE_IMAGE" "$@"
}

# Run the engine read-only on a list file kept in the state dir: `langs` or `ask`.
#   qs_engine_query <langs|ask> <list-file>
qs_engine_query() {
  local what="$1" list="$2" root state
  root="$(qs_repo_root)"; state="$(dirname "$list")"
  qs_docker_opts
  docker run "${QS_DOCKER_OPTS[@]}" -e "QS_FILES_FROM=/qs-state/$(basename "$list")" \
    -v "$(qs_hostpath "$root"):/workspace:ro" -v "$(qs_hostpath "$state"):/qs-state:ro" -w /workspace \
    "$QUALITY_SUITE_IMAGE" "$what" 2>/dev/null
}

# Add an image layer installing the missing languages (network only during this build).
# why: incremental layers keep earlier installs cached; past QS_MAX_LAYERS the image is
# rebuilt from the base in one layer (Docker caps layers at ~127). --progress=plain keeps
# the installer's messages visible; tools that failed are reported (and retried with
# QS_RETRY_FAILED=1) instead of blocking the commit.
qs_install_langs() {
  local have want layers from all nc=() t todo=()
  qs_lock
  have="$(qs_label "$QUALITY_SUITE_IMAGE" qs.langs)"
  # why: another repository may have installed some of them while this one waited for the lock
  for t in "$@"; do
    case " $have " in *" $t "*) [ "${QS_RETRY_FAILED:-0}" = 1 ] && todo+=("$t") ;; *) todo+=("$t") ;; esac
  done
  if [ "${#todo[@]}" -eq 0 ]; then qs_unlock; return 0; fi
  set -- "${todo[@]}"
  layers="$(qs_label "$QUALITY_SUITE_IMAGE" qs.layers)"; layers="${layers:-0}"
  all="$(printf '%s\n' $have "$@" | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//')"
  from="$QUALITY_SUITE_IMAGE"; want="$*"
  if [ "$layers" -ge "$QS_MAX_LAYERS" ]; then
    from="$QS_BASE_IMAGE"; want="$all"; layers=0
    echo "[quality-suite] Compacting the image (${QS_MAX_LAYERS} layers reached)..." >&2
  fi
  [ "${QS_REBUILD:-0}" = "1" ] && nc=(--no-cache)
  echo "[quality-suite] Installing tools for: ${*} (one-time, needs network)..." >&2
  local before log="$QS_HOME/install.log"
  before="$(docker image inspect -f '{{.Id}}' "$QUALITY_SUITE_IMAGE" 2>/dev/null || true)"
  printf 'FROM %s\nUSER root\nRUN qs-install %s\nUSER quality\n' "$from" "$want" \
    | docker build ${nc[@]+"${nc[@]}"} ${QS_BUILD_OPTS[@]+"${QS_BUILD_OPTS[@]}"} --progress=plain -t "$QUALITY_SUITE_IMAGE" \
        --label "qs.langs=${all}" --label "qs.layers=$((layers + 1))" - 2>&1 \
    | tee "$log" | grep -E '\[qs-install\] (WARN|ERROR|INFO installed)' >&2 || true
  # why: a failed build keeps the previous image; say so instead of retrying silently every commit
  if [ "$(docker image inspect -f '{{.Id}}' "$QUALITY_SUITE_IMAGE" 2>/dev/null || true)" = "$before" ]; then
    echo "[quality-suite] ERROR: the tools for '${*}' could not be added to the image; built-in checks run" \
         "meanwhile and the next commit retries. Full log: $log" >&2
    grep -vE '^#[0-9]+ (sha256|extracting|DONE|CACHED|\[internal\])' "$log" | tail -n 8 | sed 's/^/    /' >&2
    qs_unlock
    return 1
  fi
  local failed
  failed="$(docker run --rm --entrypoint sh "$QUALITY_SUITE_IMAGE" -c \
    'ls /opt/qs/state 2>/dev/null | sed -n "s/^failed\.//p"' 2>/dev/null | tr '\n' ' ')"
  if [ -n "$failed" ]; then
    echo "[quality-suite] WARN: not installed: ${failed}(built-in checks cover them; retry: QS_RETRY_FAILED=1 git commit)" >&2
  fi
  qs_unlock
}

# file:// URI of the JSON Schema on the host, so editors validate .quality-rules.json.
qs_schema_uri() {
  local p="${QUALITY_SUITE_DIR}/schema/quality-rules.schema.json"
  if command -v cygpath >/dev/null 2>&1; then echo "file:///$(cygpath -m "$p")"; else echo "file://$p"; fi
}
