# syntax=docker/dockerfile:1

# Back up Docker volumes and PostgreSQL databases to S3.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Global ARGs — available to all FROM directives.
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.44

# ── Supercronic build stage ────────────────────────────────────────────────
# Builds supercronic from source with Go 1.26.2, which patches:
#   CVE-2026-32280 (crypto/x509 DoS) HIGH
#   CVE-2026-32281 (crypto/x509 DoS) HIGH
#   CVE-2026-32283 (TLS key update DoS) HIGH
#   CVE-2026-33810 (crypto/x509 cert validation bypass) HIGH
# Remove this stage and restore the wget installation once an upstream
# supercronic release ships with Go >= 1.26.2 (or >= 1.25.9).
FROM golang:1.26.2-alpine AS supercronic-builder
ARG SUPERCRONIC_VERSION
RUN CGO_ENABLED=0 go install github.com/aptible/supercronic@${SUPERCRONIC_VERSION}

# ── Final image ────────────────────────────────────────────────────────────

# Pin the Alpine minor version so Dependabot can track base-image updates
# and bumps are explicit, reviewable changes rather than silent upgrades.
FROM alpine:3.23

ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG UID=10001
ARG SUPERCRONIC_VERSION

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

# Install supercronic built with Go 1.26.2 (patches CVE-2026-32280,
# CVE-2026-32281, CVE-2026-32283, CVE-2026-33810 via Go stdlib upgrade).
COPY --from=supercronic-builder --chmod=755 /go/bin/supercronic /usr/local/bin/

# Install required utilities and configure environment.
# hadolint ignore=DL3018,SC2261,SC3041,DL3059
RUN set -Eeux; \
    apk update && \
    apk upgrade --no-cache --no-interactive && \
    apk add --no-cache --no-interactive --upgrade \
        'aws-cli>2.20' \
        'bash>5.2' \
        'bzip2>1.0' \
        'bzip3>1.3' \
        'docker-cli>24' \
        'gnupg>2.4' \
        'gzip>1.12' \
        'lzop>1.04' \
        'pigz>2.8' \
        'postgresql-client' \
        'py3-cryptography>44.0' \
        'py3-urllib3>1.25' \
        'xz>5.6' \
        'zip>3.0' \
        && \
    adduser \
        --disabled-password --gecos "" --shell "/sbin/nologin" \
        --uid "${UID}" pg-volume-backup && \
    install -d -m 0700 -o pg-volume-backup \
        /home/pg-volume-backup/.gnupg && \
    install -m 0600 -o pg-volume-backup /dev/null \
        /home/pg-volume-backup/.gnupg/pubring.kbx && \
    rm -f /var/spool/cron/crontabs && \
    install -d -m 0755 -o pg-volume-backup /var/spool/cron/crontabs && \
    mkdir -pv /usr/local/include/bash && \
    ln -sf /usr/local/bin/common-functions \
        /usr/local/include/bash/common-functions && \
    mkdir -p /usr/local/share/pg-volume-backup && \
    printf '%s\n' "${VERSION}" \
        > /usr/local/share/pg-volume-backup/version && \
    true

COPY --chmod=755 ./src/bin/* /usr/local/bin/
COPY --chmod=755 ./src/common-functions /usr/local/bin/

USER pg-volume-backup

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]
