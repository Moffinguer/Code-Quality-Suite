#!/usr/bin/env bash
# entrypoint.sh - language-agnostic dispatcher. Groups the given files (relative to
# /workspace) by type (extension, name, or shebang) and runs each language handler
# IN PARALLEL. The run finishes only when every handler has finished, and exits
# non-zero if any failed. Per-language output is printed grouped, not interleaved.
set -uo pipefail

SUITE_DIR="${SUITE_DIR:-/opt/quality-suite}"
HANDLERS_DIR="${SUITE_DIR}/handlers"
[[ "$#" -eq 0 ]] && { echo "[quality-suite] Nothing to process."; exit 0; }

declare -a java_files=() md_files=() xml_files=() web_files=() jsp_files=() docker_files=()
declare -a perl_files=() sql_files=() python_files=() c_cpp_files=() shell_files=()
declare -a toml_files=() yaml_files=() rst_files=() lua_files=() zig_files=() clojure_files=()
declare -a vim_files=() prop_files=() go_files=() rust_files=() php_files=() tex_files=()
declare -a hs_files=() erl_files=() env_files=() unhandled_files=()

for f in "$@"; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  shebang=""
  if [[ -r "$f" && -s "$f" ]]; then
    read -r first_line < "$f" 2>/dev/null || first_line=""
    [[ "$first_line" =~ ^#! ]] && shebang="$first_line"
  fi
  case "$f" in
    *.java) java_files+=("$f") ;;
    *.md|*.markdown) md_files+=("$f") ;;
    *.xml) xml_files+=("$f") ;;
    *.html|*.htm|*.xhtml|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.css|*.scss) web_files+=("$f") ;;
    *.jsp) jsp_files+=("$f") ;;
    *.pl|*.pm|*.t) perl_files+=("$f") ;;
    *.sql) sql_files+=("$f") ;;
    *.py) python_files+=("$f") ;;
    *.c|*.cpp|*.cc|*.cxx|*.h|*.hpp|*.hh) c_cpp_files+=("$f") ;;
    *.sh|*.bash) shell_files+=("$f") ;;
    *.toml) toml_files+=("$f") ;;
    *.yaml|*.yml) yaml_files+=("$f") ;;
    *.rst) rst_files+=("$f") ;;
    *.lua) lua_files+=("$f") ;;
    *.zig|*.zon) zig_files+=("$f") ;;
    *.clj|*.cljs|*.cljc|*.edn) clojure_files+=("$f") ;;
    *.vim) vim_files+=("$f") ;;
    *.properties) prop_files+=("$f") ;;
    *.go) go_files+=("$f") ;;
    *.rs) rust_files+=("$f") ;;
    *.php|*.phtml) php_files+=("$f") ;;
    *.tex|*.latex|*.sty|*.cls) tex_files+=("$f") ;;
    *.hs|*.lhs) hs_files+=("$f") ;;
    *.erl|*.hrl) erl_files+=("$f") ;;
    *.env|*.env.*) env_files+=("$f") ;;
    *)
      if [[ "$shebang" =~ perl ]]; then perl_files+=("$f")
      elif [[ "$shebang" =~ python ]]; then python_files+=("$f")
      elif [[ "$shebang" =~ lua ]]; then lua_files+=("$f")
      elif [[ "$shebang" =~ php ]]; then php_files+=("$f")
      elif [[ "$shebang" =~ (bash|sh|zsh|ksh) ]]; then shell_files+=("$f")
      else
        case "$base" in
          Dockerfile|Dockerfile.*|*.Dockerfile|Containerfile|Containerfile.*) docker_files+=("$f") ;;
          .env|.env.*) env_files+=("$f") ;;
          .vimrc|vimrc|.gvimrc) vim_files+=("$f") ;;
          *) unhandled_files+=("$f") ;;
        esac
      fi
      ;;
  esac
done

pids=(); logs=()
launch() {
  local name="$1" handler="$2"; shift 2
  local lf; lf="$(mktemp)"
  { echo "[quality-suite] ${name}: $# file(s)"; "${handler}" "$@"; } >"$lf" 2>&1 &
  pids+=("$!"); logs+=("$lf")
}

[[ ${#java_files[@]}   -gt 0 ]] && launch "Java"       "${HANDLERS_DIR}/java.sh"       "${java_files[@]}"
[[ ${#md_files[@]}     -gt 0 ]] && launch "Markdown"   "${HANDLERS_DIR}/markdown.sh"   "${md_files[@]}"
[[ ${#xml_files[@]}    -gt 0 ]] && launch "XML"        "${HANDLERS_DIR}/xml.sh"        "${xml_files[@]}"
[[ ${#web_files[@]}    -gt 0 ]] && launch "Web"        "${HANDLERS_DIR}/web.sh"        "${web_files[@]}"
[[ ${#jsp_files[@]}    -gt 0 ]] && launch "JSP"        "${HANDLERS_DIR}/jsp.sh"        "${jsp_files[@]}"
[[ ${#docker_files[@]} -gt 0 ]] && launch "Dockerfile" "${HANDLERS_DIR}/dockerfile.sh" "${docker_files[@]}"
[[ ${#perl_files[@]}   -gt 0 ]] && launch "Perl"       "${HANDLERS_DIR}/perl.sh"       "${perl_files[@]}"
[[ ${#sql_files[@]}    -gt 0 ]] && launch "SQL"        "${HANDLERS_DIR}/sql.sh"        "${sql_files[@]}"
[[ ${#python_files[@]} -gt 0 ]] && launch "Python"     "${HANDLERS_DIR}/python.sh"     "${python_files[@]}"
[[ ${#c_cpp_files[@]}  -gt 0 ]] && launch "C/C++"      "${HANDLERS_DIR}/c_cpp.sh"      "${c_cpp_files[@]}"
[[ ${#shell_files[@]}  -gt 0 ]] && launch "Shell"      "${HANDLERS_DIR}/shell.sh"      "${shell_files[@]}"
[[ ${#toml_files[@]}   -gt 0 ]] && launch "TOML"       "${HANDLERS_DIR}/toml.sh"       "${toml_files[@]}"
[[ ${#yaml_files[@]}   -gt 0 ]] && launch "YAML"       "${HANDLERS_DIR}/yaml.sh"       "${yaml_files[@]}"
[[ ${#rst_files[@]}    -gt 0 ]] && launch "reST"       "${HANDLERS_DIR}/rst.sh"        "${rst_files[@]}"
[[ ${#lua_files[@]}    -gt 0 ]] && launch "Lua"        "${HANDLERS_DIR}/lua.sh"        "${lua_files[@]}"
[[ ${#zig_files[@]}    -gt 0 ]] && launch "Zig"        "${HANDLERS_DIR}/zig.sh"        "${zig_files[@]}"
[[ ${#clojure_files[@]} -gt 0 ]] && launch "Clojure"   "${HANDLERS_DIR}/clojure.sh"    "${clojure_files[@]}"
[[ ${#vim_files[@]}    -gt 0 ]] && launch "Vimscript"  "${HANDLERS_DIR}/vim.sh"        "${vim_files[@]}"
[[ ${#prop_files[@]}   -gt 0 ]] && launch "Properties" "${HANDLERS_DIR}/properties.sh" "${prop_files[@]}"
[[ ${#go_files[@]}     -gt 0 ]] && launch "Go"         "${HANDLERS_DIR}/go.sh"         "${go_files[@]}"
[[ ${#rust_files[@]}   -gt 0 ]] && launch "Rust"       "${HANDLERS_DIR}/rust.sh"       "${rust_files[@]}"
[[ ${#php_files[@]}    -gt 0 ]] && launch "PHP"        "${HANDLERS_DIR}/php.sh"        "${php_files[@]}"
[[ ${#tex_files[@]}    -gt 0 ]] && launch "TeX"        "${HANDLERS_DIR}/tex.sh"        "${tex_files[@]}"
[[ ${#hs_files[@]}     -gt 0 ]] && launch "Haskell"    "${HANDLERS_DIR}/haskell.sh"    "${hs_files[@]}"
[[ ${#erl_files[@]}    -gt 0 ]] && launch "Erlang"     "${HANDLERS_DIR}/erlang.sh"     "${erl_files[@]}"
[[ ${#env_files[@]}    -gt 0 ]] && launch "env"        "${HANDLERS_DIR}/env.sh"        "${env_files[@]}"

overall_rc=0; i=0
for pid in "${pids[@]}"; do
  wait "$pid" || overall_rc=1
  cat "${logs[$i]}"; rm -f "${logs[$i]}"
  i=$((i+1))
done

[[ ${#unhandled_files[@]} -gt 0 ]] && echo "[quality-suite] No handler yet (skipped): ${unhandled_files[*]}"
exit "${overall_rc}"
