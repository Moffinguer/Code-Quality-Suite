# syntax=docker/dockerfile:1
# Code Quality Suite - MODULAR image. It installs only the tools of the languages
# enabled with --build-arg ENABLE_<LANG>=1 (build-image.sh sets them from the
# detected languages). An empty project yields a minimal base image.
#
# Groups: JAVA, WEB, MARKDOWN, XML, DOCKER, PERL, SQL, PYTHON, CPP, SHELL
#   (NODE and PYVENV are derived; build-image.sh enables them when needed)
#
# why: pin the base by DIGEST in production for reproducibility:
#   FROM ubuntu:24.04@sha256:<digest>
#   (get it with: docker buildx imagetools inspect ubuntu:24.04)
FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Per-language enable flags (0/1)
ARG ENABLE_JAVA=0
ARG ENABLE_WEB=0
ARG ENABLE_MARKDOWN=0
ARG ENABLE_XML=0
ARG ENABLE_DOCKER=0
ARG ENABLE_PERL=0
ARG ENABLE_SQL=0
ARG ENABLE_PYTHON=0
ARG ENABLE_CPP=0
ARG ENABLE_SHELL=0
# Derived: Node shared by web/markdown; the Python venv by python/sql.
ARG ENABLE_NODE=0
ARG ENABLE_PYVENV=0

# Third-party tool versions
ARG GJF_VERSION=1.28.0
ARG CHECKSTYLE_VERSION=13.8.0
ARG PMD_VERSION=7.26.0
ARG HADOLINT_VERSION=2.14.0
ARG NODE_VERSION=20.18.1
ARG MARKDOWNLINT_VERSION=0.23.2

ENV TOOLS_DIR=/opt/tools
ENV SUITE_DIR=/opt/quality-suite
ENV WEBTOOLS_DIR=/opt/webtools

# Minimal base plus the apt packages of the enabled languages (single layer)
RUN set -u; \
    pkgs="bash git curl ca-certificates unzip xz-utils"; \
    if [ "$ENABLE_XML" = "1" ];    then pkgs="$pkgs libxml2-utils"; fi; \
    if [ "$ENABLE_PERL" = "1" ];   then pkgs="$pkgs perl cpanminus perltidy libperl-critic-perl"; fi; \
    if [ "$ENABLE_CPP" = "1" ];    then pkgs="$pkgs clang-format clang-tidy cppcheck"; fi; \
    if [ "$ENABLE_SHELL" = "1" ];  then pkgs="$pkgs shfmt shellcheck"; fi; \
    if [ "$ENABLE_PYVENV" = "1" ]; then pkgs="$pkgs python3 python3-venv python3-pip"; fi; \
    if [ "$ENABLE_JAVA" = "1" ];   then pkgs="$pkgs openjdk-21-jdk-headless"; fi; \
    apt-get update && apt-get install -y --no-install-recommends $pkgs \
 && rm -rf /var/lib/apt/lists/*

# Download helper with retries and optional checksum verification
COPY <<'SCRIPT' /usr/local/bin/_dl
#!/usr/bin/env bash
set -euo pipefail
dl()     { curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$1" "$2"; }
verify() {
  if [[ -n "${2:-}" ]]; then echo "$2  $1" | sha256sum -c -;
  else echo "WARN: no pinned checksum for $1"; fi
}
"$@"
SCRIPT
RUN chmod +x /usr/local/bin/_dl

# Java: google-java-format + Checkstyle + PMD
RUN if [ "$ENABLE_JAVA" = "1" ]; then \
      mkdir -p "${TOOLS_DIR}" && \
      _dl dl "${TOOLS_DIR}/google-java-format.jar" \
        "https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar" && \
      _dl dl "${TOOLS_DIR}/checkstyle.jar" \
        "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-${CHECKSTYLE_VERSION}/checkstyle-${CHECKSTYLE_VERSION}-all.jar" && \
      _dl dl "${TOOLS_DIR}/pmd.zip" \
        "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" && \
      unzip -q "${TOOLS_DIR}/pmd.zip" -d "${TOOLS_DIR}" && \
      mv "${TOOLS_DIR}/pmd-bin-${PMD_VERSION}" "${TOOLS_DIR}/pmd" && \
      rm "${TOOLS_DIR}/pmd.zip"; \
    fi
ENV PATH="${TOOLS_DIR}/pmd/bin:${PATH}"

# hadolint
RUN if [ "$ENABLE_DOCKER" = "1" ]; then \
      arch="$(dpkg --print-architecture)"; \
      case "$arch" in amd64) harch=x86_64;; arm64) harch=arm64;; *) echo "unsupported arch: $arch"; exit 1;; esac; \
      _dl dl /usr/local/bin/hadolint \
        "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${harch}" && \
      chmod +x /usr/local/bin/hadolint; \
    fi

# Node.js (needed by web and/or markdown)
RUN if [ "$ENABLE_NODE" = "1" ]; then \
      arch="$(dpkg --print-architecture)"; \
      case "$arch" in amd64) narch=x64;; arm64) narch=arm64;; *) echo "unsupported arch: $arch"; exit 1;; esac; \
      _dl dl /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${narch}.tar.xz" && \
      mkdir -p /opt/node && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 && rm /tmp/node.tar.xz; \
    fi
ENV PATH="/opt/node/bin:${PATH}"

# markdownlint-cli2
RUN if [ "$ENABLE_MARKDOWN" = "1" ]; then \
      npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}" && npm cache clean --force; \
    fi

# Web tools: Prettier, ESLint, Stylelint, html-validate
COPY webtools/package.json ${WEBTOOLS_DIR}/package.json
RUN if [ "$ENABLE_WEB" = "1" ]; then \
      cd ${WEBTOOLS_DIR} && npm install --no-audit --no-fund && npm cache clean --force; \
    fi
COPY webtools/.prettierrc.json webtools/eslint.config.mjs webtools/.stylelintrc.json webtools/.htmlvalidate.json ${WEBTOOLS_DIR}/

# venv + SQLFluff (Oracle) + Python tools
RUN if [ "$ENABLE_PYVENV" = "1" ]; then python3 -m venv /opt/venv; fi
ENV PATH="/opt/venv/bin:${PATH}"
RUN if [ "$ENABLE_SQL" = "1" ];    then pip install --no-cache-dir sqlfluff; fi
RUN if [ "$ENABLE_PYTHON" = "1" ]; then pip install --no-cache-dir black autopep8 isort pylint mypy; fi

# PerlImports
RUN if [ "$ENABLE_PERL" = "1" ]; then cpanm --notest App::perlimports || true; fi

# Suite layout: dispatcher + handlers + configs
COPY entrypoint.sh ${SUITE_DIR}/entrypoint.sh
COPY handlers/     ${SUITE_DIR}/handlers/
COPY config/       ${SUITE_DIR}/config/
RUN chmod +x ${SUITE_DIR}/entrypoint.sh ${SUITE_DIR}/handlers/*.sh

# Non-root user
RUN useradd --create-home --uid 1001 quality
USER quality

WORKDIR /workspace
ENTRYPOINT ["/opt/quality-suite/entrypoint.sh"]
