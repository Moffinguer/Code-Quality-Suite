#!/usr/bin/env bash
# ai-skills.sh - add community skills (folders with a SKILL.md, the format of Claude Code, Codex,
# OpenCode...) from a GitHub repository to this project, pinned to the exact commit.
#   ai-skills.sh list <owner/repo>[@ref]                  skills offered by that repository
#   ai-skills.sh add  <owner/repo>[@ref] <skill>... [--force]
#   ai-skills.sh installed                               installed skills and where they came from
# Skills go to .agents/skills/<name>/ (Codex, OpenCode) with a .source file (repository, ref,
# commit, path, date), then ai-sync.sh copies them to .claude/skills/ (Claude Code).
# A skill can make the agent run its scripts: read SKILL.md and its files before committing them.
# Update one later: ai-skills.sh add <owner/repo>@<new ref> <skill> --force
set -euo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() { echo "[ai-skills] $*" >&2; exit 1; }
say() { echo "[ai-skills] $*"; }
FORCE=0 ARGS=()
for a in "$@"; do case "$a" in --force) FORCE=1 ;; *) ARGS+=("$a") ;; esac; done
set -- ${ARGS[@]+"${ARGS[@]}"}
CMD="${1:-}"; shift || true
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run it inside the project (a git repository)"
DEST="$REPO_ROOT/.agents/skills"

fetch() {  # <owner/repo>[@ref] -> sets SRC (checkout dir), SRC_REPO, SRC_REF, SRC_COMMIT
  local spec="$1"
  SRC_REPO="${spec%@*}"; SRC_REF=""; [ "$spec" != "$SRC_REPO" ] && SRC_REF="${spec#*@}"
  case "$SRC_REPO" in */*) ;; *) die "expected owner/repo, got '$SRC_REPO'" ;; esac
  case "$SRC_REPO" in https://*|git@*) ;; *) SRC_URL="https://github.com/$SRC_REPO.git" ;; esac
  SRC_URL="${SRC_URL:-$SRC_REPO}"
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  git -C "$SRC" init -q
  # why fetch, not clone: one shallow fetch works for a branch, a tag or a commit id alike
  git -C "$SRC" fetch -q --depth 1 "$SRC_URL" "${SRC_REF:-HEAD}" 2>/dev/null \
    || die "cannot fetch $SRC_URL${SRC_REF:+ at $SRC_REF} (name, ref or network?)"
  git -C "$SRC" -c advice.detachedHead=false checkout -q FETCH_HEAD
  SRC_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
}

skills_in() {  # <dir> -> "name<TAB>relative path<TAB>description" per SKILL.md
  local root="$1" f d name desc
  while IFS= read -r -d '' f; do
    d="$(dirname "$f")"
    # why awk reads the file itself: "tr < f | awk ... exit" dies of SIGPIPE on long files (pipefail)
    name="$(awk 'NR > 1 && /^---/ { exit } { sub(/\r$/, "") } /^name:/ { sub(/^name:[ \t]*/, ""); gsub(/["\047]/, ""); print; exit }' "$f")"
    [ -n "$name" ] || name="$(basename "$d")"
    # descriptions may be YAML block scalars (">", "|-") continued on indented lines
    desc="$(awk 'NR > 1 && /^---/ { exit } { sub(/\r$/, "") }
      /^description:/ { v = $0; sub(/^description:[ \t]*/, "", v); if (v !~ /^[>|][-+]?$/) { print v; exit } blk = 1; next }
      blk && /^[ \t]+/ { sub(/^[ \t]+/, ""); printf "%s ", $0; next } blk { exit }' "$f")"
    desc="${desc//\"/}"; desc="${desc:0:90}"
    printf '%s\t%s\t%s\n' "$name" "${d#"$root"/}" "$desc"
  done < <(find "$root" -name SKILL.md -not -path '*/.git/*' -print0) | LC_ALL=C sort
}

case "$CMD" in
  list)
    [ -n "${1:-}" ] || die "usage: ai-skills.sh list <owner/repo>[@ref]"
    fetch "$1"
    say "$SRC_REPO @ ${SRC_COMMIT:0:12}:"
    skills_in "$SRC" | awk -F'\t' '{ printf "  %-28s %s\n", $1, $3 }'
    ;;
  add)
    [ "$#" -ge 2 ] || die "usage: ai-skills.sh add <owner/repo>[@ref] <skill>... [--force]"
    fetch "$1"; shift
    mkdir -p "$DEST"
    all="$(skills_in "$SRC")"; added=0
    for want in "$@"; do
      line="$(awk -F'\t' -v w="$want" '$1 == w' <<<"$all" | head -n1)"
      [ -n "$line" ] || { echo "[ai-skills] '$want' is not in $SRC_REPO (ai-skills.sh list $SRC_REPO)" >&2; continue; }
      IFS=$'\t' read -r name path _ <<<"$line"
      if [ -e "$DEST/$name" ] && [ "$FORCE" != 1 ]; then
        say "$name already installed ($(sed -n 's/^commit=//p' "$DEST/$name/.source" 2>/dev/null | cut -c1-12)); --force replaces it"
        continue
      fi
      rm -rf "${DEST:?}/$name"; cp -R "$SRC/$path" "$DEST/$name"; rm -rf "$DEST/$name/.git"
      printf 'repo=%s\nref=%s\ncommit=%s\npath=%s\ndate=%s\n' "$SRC_REPO" "${SRC_REF:-HEAD}" "$SRC_COMMIT" \
        "$path" "$(date +%Y-%m-%d)" > "$DEST/$name/.source"
      scripts="$(find "$DEST/$name" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ps1' \) | wc -l | tr -d ' ')"
      say "added $name from $SRC_REPO@${SRC_COMMIT:0:12}$([ "$scripts" -gt 0 ] && echo " ($scripts script(s): review them)")"
      added=$((added + 1))
    done
    [ "$added" -gt 0 ] && bash "$SUITE/scripts/ai-sync.sh" "$REPO_ROOT"
    [ "$added" -gt 0 ] && say "review before committing: git diff --stat -- .agents/skills .claude/skills"
    ;;
  installed)
    [ -d "$DEST" ] || { say "no skills in .agents/skills"; exit 0; }
    for d in "$DEST"/*/; do
      n="$(basename "$d")"
      if [ -f "$d/.source" ]; then
        printf '  %-28s %s@%s\n' "$n" "$(sed -n 's/^repo=//p' "$d/.source")" "$(sed -n 's/^commit=//p' "$d/.source" | cut -c1-12)"
      else printf '  %-28s (this project)\n' "$n"; fi
    done
    ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
