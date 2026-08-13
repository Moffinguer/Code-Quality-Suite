# syntax=docker/dockerfile:1
# =============================================================================
# Code Quality Suite — imagen base con soporte para Java, Web, Markdown, XML,
# Dockerfile, Perl, SQL (Oracle), Python, C/C++ y Shell.
# =============================================================================

FROM eclipse-temurin:21-jdk-noble

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GJF_VERSION=1.28.0
ARG CHECKSTYLE_VERSION=13.8.0
ARG PMD_VERSION=7.26.0
ARG HADOLINT_VERSION=2.14.0
ARG NODE_VERSION=20.18.1
ARG MARKDOWNLINT_VERSION=0.23.2

ARG GJF_SHA256=""
ARG CHECKSTYLE_SHA256=""
ARG PMD_SHA256=""
ARG HADOLINT_SHA256=""

ENV TOOLS_DIR=/opt/tools
ENV SUITE_DIR=/opt/quality-suite
ENV WEBTOOLS_DIR=/opt/webtools

# --- Paquetes de sistema y utilidades de lenguajes ---------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl unzip git bash ca-certificates xz-utils libxml2-utils \
      perl cpanminus perltidy libperl-critic-perl \
      python3 python3-pip python3-venv \
      clang-format clang-tidy cppcheck shellcheck shfmt \
 && rm -rf /var/lib/apt/lists/*

# --- Helper de descarga --------------------------------------------------------
COPY <<'SCRIPT' /usr/local/bin/_dl
#!/usr/bin/env bash
set -euo pipefail
dl()     { curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$1" "$2"; }
verify() {
  if [[ -n "${2:-}" ]]; then echo "$2  $1" | sha256sum -c -;
  else echo "AVISO: sin checksum fijado para $1"; fi
}
"$@"
SCRIPT
RUN chmod +x /usr/local/bin/_dl

# --- Instalación de PerlImports ------------------------------------------------
RUN cpanm --notest App::perlimports || true

# --- Herramientas de Python y SQLFluff (Oracle) ------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
RUN pip install --no-cache-dir \
      sqlfluff \
      black autopep8 pybetter unify eradicate isort ssort teyit pylint mypy

# --- Herramientas Java --------------------------------------------------------
RUN mkdir -p "${TOOLS_DIR}" \
 && /usr/local/bin/_dl dl "${TOOLS_DIR}/google-java-format.jar" \
      "https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar" \
 && /usr/local/bin/_dl verify "${TOOLS_DIR}/google-java-format.jar" "${GJF_SHA256}" \
 && /usr/local/bin/_dl dl "${TOOLS_DIR}/checkstyle.jar" \
      "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-${CHECKSTYLE_VERSION}/checkstyle-${CHECKSTYLE_VERSION}-all.jar" \
 && /usr/local/bin/_dl verify "${TOOLS_DIR}/checkstyle.jar" "${CHECKSTYLE_SHA256}" \
 && /usr/local/bin/_dl dl "${TOOLS_DIR}/pmd.zip" \
      "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" \
 && /usr/local/bin/_dl verify "${TOOLS_DIR}/pmd.zip" "${PMD_SHA256}" \
 && unzip -q "${TOOLS_DIR}/pmd.zip" -d "${TOOLS_DIR}" \
 && mv "${TOOLS_DIR}/pmd-bin-${PMD_VERSION}" "${TOOLS_DIR}/pmd" \
 && rm "${TOOLS_DIR}/pmd.zip"

# --- hadolint -----------------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64) harch=x86_64;; arm64) harch=arm64;; *) exit 1;; esac; \
    /usr/local/bin/_dl dl /usr/local/bin/hadolint \
      "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${harch}"; \
    /usr/local/bin/_dl verify /usr/local/bin/hadolint "${HADOLINT_SHA256}"; \
    chmod +x /usr/local/bin/hadolint

# --- Node + markdownlint -------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64) narch=x64;; arm64) narch=arm64;; *) exit 1;; esac; \
    /usr/local/bin/_dl dl /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${narch}.tar.xz"; \
    mkdir -p /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:${TOOLS_DIR}/pmd/bin:${PATH}"
RUN npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}" \
 && npm cache clean --force

# --- Webtools -----------------------------------------------------------------
COPY webtools/package.json ${WEBTOOLS_DIR}/package.json
RUN cd ${WEBTOOLS_DIR} && npm install --no-audit --no-fund && npm cache clean --force
COPY webtools/.prettierrc.json webtools/eslint.config.mjs webtools/.stylelintrc.json webtools/.htmlvalidate.json ${WEBTOOLS_DIR}/

# --- Estructura de la Suite ----------------------------------------------------
COPY entrypoint.sh ${SUITE_DIR}/entrypoint.sh
COPY handlers/     ${SUITE_DIR}/handlers/
COPY config/       ${SUITE_DIR}/config/
RUN chmod +x ${SUITE_DIR}/entrypoint.sh ${SUITE_DIR}/handlers/*.sh

RUN useradd --create-home --uid 1001 quality
USER quality

WORKDIR /workspace
ENTRYPOINT ["/opt/quality-suite/entrypoint.sh"]
