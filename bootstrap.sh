#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — instalación completa a partir de un repo (o clonándolo):
#   1) clona el repo si le pasas una URL
#   2) crea/actualiza .gitattributes (bloque gestionado)
#   3) detecta parámetros del proyecto (p.ej. versión de Java para PMD); si no
#      puede, los pregunta la primera vez y los PERSISTE en quality-suite.env
#   4) construye la imagen e instala los hooks
# Idempotente: re-ejecutarlo respeta lo ya definido.
#
#   Uso:  ./bootstrap.sh <git-url | ruta-repo> [dir-destino]
#   Destino por defecto al clonar: $QUALITY_WORKSPACE/<nombre> si esta definido.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC="${1:?uso: ./bootstrap.sh <git-url|ruta-repo> [dir-destino]}"
DEST="${2:-}"

# --- 1) Resolver / clonar repo ------------------------------------------------
case "$SRC" in
  http://*|https://*|git@*|ssh://*)
    base="$(basename "${SRC%.git}")"
    if [ -n "$DEST" ]; then target="$DEST"
    elif [ -n "${QUALITY_WORKSPACE:-}" ]; then target="${QUALITY_WORKSPACE%/}/$base"
    else target="$base"; fi
    if [ -d "$target/.git" ]; then echo "[bootstrap] '$target' ya existe; lo reutilizo.";
    else echo "[bootstrap] Clonando $SRC -> $target ..."; git clone "$SRC" "$target"; fi
    REPO="$(cd "$target" && pwd)" ;;
  *) REPO="$(cd "$SRC" && pwd)" ;;
esac
echo "[bootstrap] Repo: $REPO"

HOOK_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)/hooks"
mkdir -p "$HOOK_DIR"
ENV_FILE="${HOOK_DIR}/quality-suite.env"

env_get() { [ -f "$ENV_FILE" ] && sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ENV_FILE" | head -n1 || true; }
env_set() { # KEY VALUE
  local k="$1" v="$2"
  if [ -f "$ENV_FILE" ] && grep -q "^$k=" "$ENV_FILE"; then
    sed -i.bak "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"; fi
}

# --- 2) .gitattributes (bloque gestionado: crea o reemplaza) ------------------
ensure_gitattributes() {
  local ga="$REPO/.gitattributes"
  local begin="# >>> code-quality-suite (gestionado) >>>"
  local end="# <<< code-quality-suite <<<"
  local block
  block="$begin
* text=auto eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
$end"
  if [ -f "$ga" ] && grep -qF "$begin" "$ga"; then
    awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$ga" > "$ga.tmp"
    printf '%s\n' "$block" >> "$ga.tmp"; mv "$ga.tmp" "$ga"
    echo "[bootstrap] .gitattributes: bloque actualizado"
  else
    [ -f "$ga" ] && printf '\n' >> "$ga"
    printf '%s\n' "$block" >> "$ga"
    echo "[bootstrap] .gitattributes: bloque añadido"
  fi
}
ensure_gitattributes

# --- 3) Parámetros del proyecto ----------------------------------------------
# Detección extensible por tecnología. Hoy: Java desde pom.xml (para PMD).
# Para otras tecnologías, añade aquí su fichero/campo (build.gradle, package.json...).
detect_java_version() {
  local pom="$REPO/pom.xml" v=""
  if [ -f "$pom" ]; then
    v="$(sed -n 's:.*<java.version>\([0-9][0-9.]*\)</java.version>.*:\1:p' "$pom" | head -n1)"
    [ -z "$v" ] && v="$(sed -n 's:.*<maven.compiler.release>\([0-9][0-9.]*\)</maven.compiler.release>.*:\1:p' "$pom" | head -n1)"
    [ -z "$v" ] && v="$(sed -n 's:.*<maven.compiler.source>\([0-9][0-9.]*\)</maven.compiler.source>.*:\1:p' "$pom" | head -n1)"
  fi
  printf '%s' "$v"
}

JV="$(env_get PMD_JAVA_VERSION)"
if [ -n "$JV" ]; then
  echo "[bootstrap] PMD_JAVA_VERSION ya definido ($JV); lo respeto."
else
  JV="$(detect_java_version)"
  if [ -n "$JV" ]; then
    echo "[bootstrap] Java detectado en pom.xml: $JV"
  else
    printf "[bootstrap] No pude detectar la versión de Java. Introdúcela (ej. 17, 21): "
    read -r JV < /dev/tty 2>/dev/null || JV=""
    [ -z "$JV" ] && JV="21"
  fi
fi

# --- 4) Imagen + hooks (install.sh preserva parámetros de usuario existentes) --
"$SCRIPT_DIR/install.sh" "$REPO"

# --- 5) Persistir el parámetro detectado/preguntado --------------------------
env_set PMD_JAVA_VERSION "$JV"
echo "[bootstrap] PMD_JAVA_VERSION=$JV guardado en $ENV_FILE"
echo "[bootstrap] Listo. Prueba:  cd \"$REPO\" && git commit"
