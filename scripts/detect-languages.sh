#!/usr/bin/env bash
# detect-languages.sh - print the language tokens a project (or file list) uses.
#   detect-languages.sh <repo_dir>         scan tracked files in the repo
#   detect-languages.sh --files f1 f2 ...  classify the given files
# Output: space-separated tokens; empty means nothing to install.
set -euo pipefail
langs=""
add(){ case " $langs " in *" $1 "*) ;; *) langs="$langs $1";; esac; }

classify(){
  local f="$1" base; base="$(basename "$f")"
  case "$f" in
    *.java) add java;;
    *.md|*.markdown) add markdown;;
    *.xml) add xml;;
    *.html|*.htm|*.xhtml|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.css|*.scss) add web;;
    *.pl|*.pm|*.t) add perl;;
    *.sql) add sql;;
    *.py) add python;;
    *.c|*.cpp|*.cc|*.cxx|*.h|*.hpp|*.hh) add cpp;;
    *.sh|*.bash) add shell;;
    *.jsp) : ;;  # no installable tool
    *)
      case "$base" in
        Dockerfile|Dockerfile.*|*.Dockerfile|Containerfile|Containerfile.*) add docker;;
      esac
      if [ -f "$f" ]; then
        local sb; sb="$(head -n1 "$f" 2>/dev/null || true)"
        case "$sb" in
          *perl*) add perl;;
          *python*) add python;;
          *bash|*/sh|*" sh"|*"env sh") add shell;;
        esac
      fi
      ;;
  esac
}

if [ "${1:-}" = "--files" ]; then
  shift; for f in "$@"; do classify "$f"; done
else
  repo="${1:-.}"
  if git -C "$repo" rev-parse >/dev/null 2>&1; then
    while IFS= read -r f; do classify "$repo/$f"; done < <(git -C "$repo" ls-files)
  else
    while IFS= read -r f; do classify "$f"; done < <(find "$repo" -type f -not -path '*/.git/*' 2>/dev/null)
  fi
fi
echo "${langs# }"
