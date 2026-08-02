#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — despachador agnostico al lenguaje.
#
# Recibe rutas de fichero (relativas a /workspace) y las agrupa por tipo
# segun la extension o el nombre, delegando en el handler correspondiente.
#
# Anadir un tipo nuevo:
#   1) crea handlers/<tipo>.sh (contrato: autoarregla in-place + analiza,
#      exit 0 si limpio, exit !=0 si hay violaciones)
#   2) instala su herramienta en el Dockerfile
#   3) anade su rama en el bucle de clasificacion de abajo
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
declare -a unhandled_files=()

for f in "$@"; do
  [[ -f "$f" ]] || continue          # ignora borrados
  base="$(basename "$f")"
  case "$f" in
    *.java)          java_files+=("$f") ;;
    *.md|*.markdown) md_files+=("$f") ;;
    *.xml)           xml_files+=("$f") ;;
    *.html|*.htm|*.xhtml|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.css|*.scss) web_files+=("$f") ;;
    *.jsp)           jsp_files+=("$f") ;;
    *)
      # Dockerfiles no siempre tienen extension: se detectan por nombre.
      case "$base" in
        Dockerfile|Dockerfile.*|*.Dockerfile|Containerfile|Containerfile.*)
                     docker_files+=("$f") ;;
        *)           unhandled_files+=("$f") ;;
      esac
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

if [[ "${#unhandled_files[@]}" -gt 0 ]]; then
  echo "[quality-suite] Sin handler todavia (ignorados): ${unhandled_files[*]}"
fi

exit "${overall_rc}"
