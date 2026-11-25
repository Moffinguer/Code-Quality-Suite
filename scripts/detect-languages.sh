#!/usr/bin/env bash
# detect-languages.sh - print the language tokens a project (or file list) uses.
#   detect-languages.sh <repo_dir>         scan tracked files in the repo
#   detect-languages.sh --files f1 f2 ...  classify the given files
# Output: space-separated tokens; empty means nothing to install.
set -euo pipefail
langs=""
# add TOKEN: append a language token to $langs once, in order of first detection.
# Arguments: $1 language token. Returns: 0. Errors: none.
add() { case " $langs " in *" $1 "*) ;; *) langs="$langs $1" ;; esac }

# classify FILE: add the language tokens of one file, from its name, its extension and, when
# those do not decide, its first line (shebang). Arguments: $1 file path. Returns: 0. Errors: none.
classify() {
	local f="$1" base
	base="$(basename "$f")"
	case "$f" in
	*.java) add java ;;
	*.md | *.markdown) add markdown ;;
	*.xml) add xml ;;
	*.html | *.htm | *.xhtml | *.js | *.jsx | *.ts | *.tsx | *.mjs | *.cjs | *.css | *.scss) add web ;;
	*.jsp) : ;;
	*.pl | *.pm | *.t) add perl ;;
	*.sql) add sql ;;
	*.py) add python ;;
	*.c | *.cpp | *.cc | *.cxx | *.h | *.hpp | *.hh) add cpp ;;
	*.sh | *.bash) add shell ;;
	*.toml) add toml ;;
	*.yaml | *.yml) add yaml ;;
	*.rst) add rst ;;
	*.lua) add lua ;;
	*.zig | *.zon) add zig ;;
	*.clj | *.cljs | *.cljc | *.edn) add clojure ;;
	*.vim) add vim ;;
	*.properties) add properties ;;
	*.go) add go ;;
	*.rs) add rust ;;
	*.php | *.phtml) add php ;;
	*.tex | *.latex | *.sty | *.cls) add tex ;;
	*.hs | *.lhs) add haskell ;;
	*.erl | *.hrl) add erlang ;;
	*.env | *.env.*) add env ;;
	*)
		case "$base" in
		Dockerfile | Dockerfile.* | *.Dockerfile | Containerfile | Containerfile.*) add docker ;;
		.env | .env.*) add env ;;
		.vimrc | vimrc | .gvimrc) add vim ;;
		esac
		if [ -f "$f" ]; then
			local sb
			sb="$(head -n1 "$f" 2>/dev/null || true)"
			case "$sb" in
			*perl*) add perl ;;
			*python*) add python ;;
			*lua*) add lua ;;
			*php*) add php ;;
			# why: *"env sh" is covered by *" sh", so it is not listed (shellcheck SC2221/SC2222)
			*bash | */sh | *" sh") add shell ;;
			esac
		fi
		;;
	esac
}

if [ "${1:-}" = "--files" ]; then
	shift
	for f in "$@"; do classify "$f"; done
else
	repo="${1:-.}"
	if git -C "$repo" rev-parse >/dev/null 2>&1; then
		while IFS= read -r f; do classify "$repo/$f"; done < <(git -C "$repo" ls-files)
	else
		while IFS= read -r f; do classify "$f"; done < <(find "$repo" -type f -not -path '*/.git/*' 2>/dev/null)
	fi
fi
echo "${langs# }"
