#!/usr/bin/env bash
# =============================================================================
# update-checksums.sh — calcula los SHA-256 de las herramientas para FIJARLOS
# en el build (proteccion supply-chain). Imprime lineas --build-arg listas.
#
# Uso:  ./scripts/update-checksums.sh
#       (respeta las mismas variables de version que el Dockerfile)
# =============================================================================
set -euo pipefail

GJF_VERSION="${GJF_VERSION:-1.28.0}"
CHECKSTYLE_VERSION="${CHECKSTYLE_VERSION:-13.8.0}"
PMD_VERSION="${PMD_VERSION:-7.26.0}"
HADOLINT_VERSION="${HADOLINT_VERSION:-2.14.0}"

arch="$(uname -m)"
case "$arch" in x86_64 | amd64) harch=x86_64 ;; aarch64 | arm64) harch=arm64 ;; *) harch=x86_64 ;; esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# sha URL: download URL over https (TLS 1.2 or later) and print its SHA-256 hash.
# Arguments: $1 URL. Returns: 0 and prints the hash. Errors: the function does not check the
# download; curl prints its own message on stderr.
sha() {
	curl --proto '=https' --tlsv1.2 -fsSL "$1" -o "$tmp/f"
	sha256sum "$tmp/f" | awk '{print $1}'
}

echo "GJF_SHA256=$(sha "https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar")"
echo "CHECKSTYLE_SHA256=$(sha "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-${CHECKSTYLE_VERSION}/checkstyle-${CHECKSTYLE_VERSION}-all.jar")"
echo "PMD_SHA256=$(sha "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip")"
echo "HADOLINT_SHA256=$(sha "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${harch}")"
echo
echo "# Ejemplo de build con checksums fijados:"
# shellcheck disable=SC1003 # why: the trailing backslash is printed literally (line continuation of the example)
echo '#   docker build \'
# shellcheck disable=SC1003 # why: the trailing backslash is printed literally (line continuation of the example)
echo '#     --build-arg GJF_SHA256=... --build-arg CHECKSTYLE_SHA256=... \'
# shellcheck disable=SC1003 # why: the trailing backslash is printed literally (line continuation of the example)
echo '#     --build-arg PMD_SHA256=... --build-arg HADOLINT_SHA256=... \'
echo "#     -t code-quality-suite:latest ."
