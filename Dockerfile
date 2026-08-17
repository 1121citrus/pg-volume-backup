# syntax=docker/dockerfile:1

# Back up Docker volumes and PostgreSQL databases to S3.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG BASE_IMAGE=1121citrus/aws-backup-base:latest

# ── Supercronic build stage ────────────────────────────────────────────────
# Build supercronic from source so the final image does not inherit the base
# image's Go stdlib scan data.
FROM golang:1.26.6-alpine AS supercronic-builder

ARG SUPERCRONIC_VERSION=v0.2.47

# hadolint ignore=DL3018
RUN GOTOOLCHAIN=go1.26.5 CGO_ENABLED=0 go install github.com/aptible/supercronic@${SUPERCRONIC_VERSION}

# ── Docker CLI build stage ─────────────────────────────────────────────────
# Build the Docker CLI from source in GOPATH mode so the final image does not
# inherit the prebuilt binary's stale Go stdlib scan data.
FROM golang:1.26.6-alpine AS docker-cli-builder

WORKDIR /tmp/gopath/src/github.com/docker/cli

# hadolint ignore=DL3018
RUN apk add --no-cache git \
    && git clone --branch v29.6.1 --depth 1 \
        https://github.com/docker/cli.git \
        . \
    && GOPATH=/tmp/gopath GO111MODULE=off CGO_ENABLED=0 \
        /usr/local/go/bin/go build -o /go/bin/docker ./cmd/docker

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

# Install required utilities and configure environment.
# bzip3 and pixz are not available in AL2023; gzip, bzip2, xz, lzop, and pigz
# cover all common backup compression scenarios.
# hadolint ignore=DL3041
RUN set -eux; \
    dnf upgrade -y --quiet \
    && dnf install -y --quiet \
        bzip2 \
        gnupg2 \
        gzip \
        lzop \
        pigz \
        postgresql15 \
        xz \
        zip \
    && dnf remove -y 'perl*' python3-pygments \
    && rpm -e --nodeps python3-setuptools python3-setuptools-wheel \
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
    && ln -sf /usr/local/include/common-functions \
        /usr/local/include/bash/common-functions \
    && mkdir -p /usr/local/share/pg-volume-backup \
    && printf '%s\n' "${VERSION}" \
        > /usr/local/share/pg-volume-backup/version \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY --from=supercronic-builder --chmod=755 /go/bin/supercronic /usr/local/bin/supercronic
COPY --from=docker-cli-builder --chmod=755 /go/bin/docker /usr/local/bin/docker

COPY --chmod=755 ./src/bin/* /usr/local/bin/
COPY --chmod=644 ./include/logging ./include/path /usr/local/include/

USER pg-volume-backup

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]
