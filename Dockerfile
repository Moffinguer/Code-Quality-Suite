# code-quality-suite BASE image: only what is needed to detect languages and install tools.
# Language tools are NOT here: the first commit that contains a language adds an image layer
# with `qs-install <lang>` (scripts/ensure-langs.sh). Analysis containers run offline.
#
# Reproducible by default: the Ubuntu image comes from base-image.lock when present (a digest
# written by `scripts/build-image.sh --pin`), and every apt install, here and in qs-install,
# reads the Ubuntu archive as it was on QS_APT_SNAPSHOT (snapshot.ubuntu.com; "off" = live).
ARG UBUNTU_IMAGE=ubuntu:24.04
FROM ${UBUNTU_IMAGE}
ARG QS_APT_SNAPSHOT=20261001T000000Z

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Management/installer tools only: python3 runs the engine and the installer, file(1) detects
# types, git/curl/unzip/xz fetch and unpack tool releases.
# why --error-on=any: apt only warns when an index fails to download, so a blocked snapshot
# server would go unnoticed and the install would fail later.
RUN o=(); apt-get update -qq \
 && if [ "$QS_APT_SNAPSHOT" != off ] \
       && apt-get update -qq --error-on=any -o "APT::Snapshot=$QS_APT_SNAPSHOT"; then \
      o=(-o "APT::Snapshot=$QS_APT_SNAPSHOT"); \
    else echo "[qs] WARN: apt snapshot '$QS_APT_SNAPSHOT' unavailable; using the live archive" >&2; \
      apt-get update -qq; fi \
 && apt-get install -y --no-install-recommends "${o[@]}" \
      bash ca-certificates curl file git python3 python3-venv python3-yaml unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

ENV QS_APT_SNAPSHOT=${QS_APT_SNAPSHOT} \
    QS_SUITE=/opt/quality-suite \
    QS_NPM=/opt/npm \
    QS_STATE=/qs-state \
    PATH=/opt/qs/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    PYTHONDONTWRITEBYTECODE=1 \
    LANG=C.UTF-8 \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=*

COPY VERSION              /opt/quality-suite/VERSION
COPY engine/              /opt/quality-suite/engine/
COPY registry/registry.json /opt/quality-suite/registry/registry.json
COPY schema/              /opt/quality-suite/schema/
COPY config/              /opt/quality-suite/config/
COPY install/qs-install   /usr/local/bin/qs-install

RUN chmod 0755 /usr/local/bin/qs-install \
 && mkdir -p /opt/qs/bin /opt/qs/state /opt/npm /qs-state /workspace \
 && chmod -R a+rX /opt/quality-suite /opt/qs \
 && useradd --create-home --uid 1001 quality

LABEL org.opencontainers.image.title="code-quality-suite" \
      qs.langs="" \
      qs.layers="0"

USER quality
WORKDIR /workspace
ENTRYPOINT ["python3", "/opt/quality-suite/engine/qs.py"]
