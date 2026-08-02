#!/usr/bin/env bash
# =============================================================================
# handlers/java.sh — gjf + checkstyle + pmd.
# QUALITY_MODE=fix   (por defecto): formatea in-place.
# QUALITY_MODE=check (pre-push):    falla si el formato no esta aplicado, no toca ficheros.
# PMD_JAVA_VERSION:  nivel de lenguaje del proyecto (indep. del JDK del contenedor).
# =============================================================================
set -euo pipefail

TOOLS_DIR="/opt/tools"
CONFIG_DIR="/opt/quality-suite/config"
GJF_JAR="${TOOLS_DIR}/google-java-format.jar"
CHECKSTYLE_JAR="${TOOLS_DIR}/checkstyle.jar"
MODE="${QUALITY_MODE:-fix}"
PMD_JAVA_VERSION="${PMD_JAVA_VERSION:-21}"

GJF_EXPORTS=(
  --add-exports jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED
  --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED
  --add-exports jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED
  --add-exports jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED
  --add-exports jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED
)

files=("$@")
[ "${#files[@]}" -eq 0 ] && exit 0
rc=0

if [ "$MODE" = "check" ]; then
  echo "  -> [java] google-java-format (check)"
  java "${GJF_EXPORTS[@]}" -jar "${GJF_JAR}" --dry-run --set-exit-if-changed "${files[@]}" || rc=1
else
  echo "  -> [java] google-java-format (--replace)"
  java "${GJF_EXPORTS[@]}" -jar "${GJF_JAR}" --replace "${files[@]}"
fi

echo "  -> [java] checkstyle"
java -Dfile.encoding=UTF-8 -jar "${CHECKSTYLE_JAR}" \
  -c "${CONFIG_DIR}/checkstyle.xml" "${files[@]}" || rc=1

echo "  -> [java] pmd (java-${PMD_JAVA_VERSION})"
list_file="$(mktemp)"
printf '%s\n' "${files[@]}" > "${list_file}"
pmd check \
  --rulesets "${CONFIG_DIR}/pmd-ruleset.xml" \
  --file-list "${list_file}" \
  --use-version "java-${PMD_JAVA_VERSION}" \
  --encoding UTF-8 --format text --no-cache || rc=1
rm -f "${list_file}"

exit "${rc}"
