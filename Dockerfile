# syntax=docker/dockerfile:1

# Back up Docker volumes and PostgreSQL databases to S3.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG BASE_IMAGE=1121citrus/aws-backup-base:latest

# ── Docker CLI build stage ─────────────────────────────────────────────────
# Extracts the statically-linked docker CLI binary from Docker's official
# image so no third-party repository is required in the final image.
FROM docker:cli AS docker-cli-source

# ── Final image ────────────────────────────────────────────────────────────
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG UID=10001

# OCI image annotations (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
LABEL org.opencontainers.image.title="pg-volume-backup" \
      org.opencontainers.image.description="Back up Docker volumes and PostgreSQL databases to S3" \
      org.opencontainers.image.url="https://github.com/1121citrus/pg-volume-backup" \
      org.opencontainers.image.source="https://github.com/1121citrus/pg-volume-backup" \
      org.opencontainers.image.vendor="1121 Citrus Avenue" \
      org.opencontainers.image.authors="James Hanlon <jim@hanlonsoftware.com>" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Copy the statically-linked docker CLI binary from the official docker:cli image.
COPY --from=docker-cli-source --chmod=755 /usr/local/bin/docker /usr/local/bin/docker

# Install required utilities and configure environment.
# bzip3 and pixz are not available in AL2023; gzip, bzip2, xz, lzop, and pigz
# cover all common backup compression scenarios.
# hadolint ignore=DL3041
RUN set -eux; \
    dnf install -y --quiet \
        bzip2 \
        gnupg2 \
        gzip \
        lzop \
        pigz \
        postgresql15 \
        xz \
        zip \
    && useradd \
        --create-home --shell /sbin/nologin \
        --uid "${UID}" pg-volume-backup \
    && install -d -m 0700 -o pg-volume-backup \
        /home/pg-volume-backup/.gnupg \
    && install -m 0600 -o pg-volume-backup /dev/null \
        /home/pg-volume-backup/.gnupg/pubring.kbx \
    && install -d -m 755 /var/spool/cron \
    && install -d -m 0755 -o pg-volume-backup /var/spool/cron/crontabs \
    && mkdir -pv /usr/local/include/bash \
    && ln -sf /usr/local/bin/common-functions \
        /usr/local/include/bash/common-functions \
    && mkdir -p /usr/local/share/pg-volume-backup \
    && printf '%s\n' "${VERSION}" \
        > /usr/local/share/pg-volume-backup/version \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY --chmod=755 ./src/bin/* /usr/local/bin/
COPY --chmod=755 ./src/common-functions /usr/local/bin/

USER pg-volume-backup

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]
