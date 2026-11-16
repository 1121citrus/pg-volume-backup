#!/usr/bin/env bats
# test/07-image-metadata.bats — verify OCI image labels and build-arg wiring.
#
# Validates via static Dockerfile analysis (no image build required):
#   - ARG VERSION, ARG GIT_COMMIT, ARG BUILD_DATE are declared
#   - All required org.opencontainers.image.* LABEL keys are present
#   - version/revision/created labels reference the correct ARG variables
#   - dnf reaches the latest AL2023 release and Go builders are patched
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    DOCKERFILE="${REPO_ROOT}/Dockerfile"
}

@test "Dockerfile declares ARG VERSION" {
    run grep -E '^ARG VERSION=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile declares ARG GIT_COMMIT" {
    run grep -E '^ARG GIT_COMMIT=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile declares ARG BUILD_DATE" {
    run grep -E '^ARG BUILD_DATE=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.title" {
    run grep -F 'org.opencontainers.image.title' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.description" {
    run grep -F 'org.opencontainers.image.description' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.url" {
    run grep -F 'org.opencontainers.image.url' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.source" {
    run grep -F 'org.opencontainers.image.source' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.vendor" {
    run grep -F 'org.opencontainers.image.vendor' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.licenses" {
    run grep -F 'org.opencontainers.image.licenses' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.authors" {
    run grep -F 'org.opencontainers.image.authors' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.version is wired to VERSION build-arg" {
    run grep -F 'org.opencontainers.image.version="${VERSION}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.revision is wired to GIT_COMMIT build-arg" {
    run grep -F 'org.opencontainers.image.revision="${GIT_COMMIT}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.created is wired to BUILD_DATE build-arg" {
    run grep -F 'org.opencontainers.image.created="${BUILD_DATE}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has USER directive (non-root)" {
    run grep -E '^USER ' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "dnf upgrade and install use --releasever=latest" {
    run grep -E 'dnf upgrade -y .*--releasever=latest' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
    run grep -E 'dnf install -y .*--releasever=latest' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Go builder stages use golang:1.27.4-alpine or newer" {
    run grep -E '^FROM golang:1\.27\.[0-3]-' "${DOCKERFILE}"
    [ "$status" -ne 0 ]
    run grep -cE '^FROM golang:[0-9.]+-alpine AS ' "${DOCKERFILE}"
    [ "$output" -eq 2 ]
}

@test "base image is pinned by sha256 digest" {
    run grep -E '^ARG BASE_IMAGE=1121citrus/aws-backup-base@sha256:[0-9a-f]{64}$' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}
