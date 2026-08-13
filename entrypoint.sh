#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — despachador agnostico al lenguaje.
#
# Recibe rutas de fichero (relativas a /workspace) y las agrupa por tipo
# segun la extension, el nombre o el contenido (shebang para scripts sin extension),
# delegando en el handler correspondiente.
# =============================================================================
set -euo pipefail

SUITE_DIR="/opt/quality-suite"
HANDLERS_DIR="${SUITE_DIR}/handlers"

if [[ "$#" -eq 0 ]]; then
  echo "[quality-suite] No hay ficheros que procesar."
  exit 0
fi

declare -a java_files=()
declare -a md_files=()
declare -a xml_files=()
declare -a web_files=()
declare -a jsp_files=()
declare -a docker_files=()
declare -a perl_files=()
declare -a sql_files=()
declare -a python_files=()
declare -a c_cpp_files=()
declare -a shell_files=()
declare -a unhandled_files=()

for f in "$@"; do
  [[ -f "$f" ]] || continue          # ignora borrados
  base="$(basename "$f")"

  # Deteccion de shebang para archivos sin extension clara o scripts ejecutables
  shebang=""
  if [[ -f "$f" && -r "$f" && -s "$f" ]]; then
    # Leemos la primera linea de forma segura sin cargar todo el archivo en memoria
    read -r first_line < "$f" 2>/dev/null || first_line=""
    if [[ "$first_line" =~ ^#! ]]; then
      shebang="$first_line"
    fi
  fi

  case "$f" in
    *.java)
      java_files+=("$f")
      ;;
    *.md|*.markdown)
      md_files+=("$f")
      ;;
    *.xml)
      xml_files+=("$f")
      ;;
    *.html|*.htm|*.xhtml|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.css|*.scss)
      web_files+=("$f")
      ;;
    *.jsp)
      jsp_files+=("$f")
      ;;
    *.pl|*.pm|*.t)
      perl_files+=("$f")
      ;;
    *.sql)
      sql_files+=("$f")
      ;;
    *.py)
      python_files+=("$f")
      ;;
    *.c|*.cpp|*.cc|*.cxx|*.h|*.hpp|*.hh)
      c_cpp_files+=("$f")
      ;;
    *.sh|*.bash)
      shell_files+=("$f")
      ;;
    *)
      # Si no tiene una extension conocida, intentamos clasificar por shebang (tipo de archivo)
      if [[ "$shebang" =~ perl ]]; then
        perl_files+=("$f")
      elif [[ "$shebang" =~ python ]]; then
        python_files+=("$f")
      elif [[ "$shebang" =~ (bash|sh|zsh|ksh) ]]; then
        shell_files+=("$f")
      else
        # Dockerfiles no siempre tienen extension: se detectan por nombre.
        case "$base" in
          Dockerfile|Dockerfile.*|*.Dockerfile|Containerfile|Containerfile.*)
            docker_files+=("$f")
            ;;
          *)
            unhandled_files+=("$f")
            ;;
        esac
      fi
      ;;
  esac
done

overall_rc=0
run_handler() {  # <nombre> <handler> <ficheros...>
  local name="$1" handler="$2"; shift 2
  echo "[quality-suite] ${name}: $# fichero(s)"
  "${handler}" "$@" || overall_rc=1
}

[[ "${#java_files[@]}"   -gt 0 ]] && run_handler "Java"       "${HANDLERS_DIR}/java.sh"       "${java_files[@]}"
[[ "${#md_files[@]}"     -gt 0 ]] && run_handler "Markdown"   "${HANDLERS_DIR}/markdown.sh"   "${md_files[@]}"
[[ "${#xml_files[@]}"    -gt 0 ]] && run_handler "XML"        "${HANDLERS_DIR}/xml.sh"        "${xml_files[@]}"
[[ "${#web_files[@]}"    -gt 0 ]] && run_handler "Web"        "${HANDLERS_DIR}/web.sh"        "${web_files[@]}"
[[ "${#jsp_files[@]}"    -gt 0 ]] && run_handler "JSP"        "${HANDLERS_DIR}/jsp.sh"        "${jsp_files[@]}"
[[ "${#docker_files[@]}" -gt 0 ]] && run_handler "Dockerfile" "${HANDLERS_DIR}/dockerfile.sh" "${docker_files[@]}"
[[ "${#perl_files[@]}"   -gt 0 ]] && run_handler "Perl"       "${HANDLERS_DIR}/perl.sh"       "${perl_files[@]}"
[[ "${#sql_files[@]}"    -gt 0 ]] && run_handler "SQL Oracle" "${HANDLERS_DIR}/sql.sh"        "${sql_files[@]}"
[[ "${#python_files[@]}" -gt 0 ]] && run_handler "Python"     "${HANDLERS_DIR}/python.sh"     "${python_files[@]}"
[[ "${#c_cpp_files[@]}"  -gt 0 ]] && run_handler "C/C++"      "${HANDLERS_DIR}/c_cpp.sh"      "${c_cpp_files[@]}"
[[ "${#shell_files[@]}"  -gt 0 ]] && run_handler "Shell"      "${HANDLERS_DIR}/shell.sh"      "${shell_files[@]}"

if [[ "${#unhandled_files[@]}" -gt 0 ]]; then
  echo "[quality-suite] Sin handler todavia (ignorados): ${unhandled_files[*]}"
fi

exit "${overall_rc}"
