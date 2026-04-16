#!/usr/bin/env bats
# test/02-pg-volume-backup.bats — test src/bin/pg-volume-backup directly.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pg-volume-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Run pg-volume-backup; extra docker flags go before IMAGE.
    run_pg_volume_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e AWS_S3_BUCKET_NAME=test-bucket \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/pg-volume-backup
    }
    export -f run_pg_volume_backup

    # Create a temp volume directory readable by the container user.
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "${TEST_TMPDIR}/vol"
    echo "test" > "${TEST_TMPDIR}/vol/file.txt"
    chmod -R o+rx "${TEST_TMPDIR}"
    export TEST_TMPDIR
}

teardown() {
    if [ -n "${TEST_TMPDIR:-}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}

# ── CLI flags ─────────────────────────────────────────────────────────────────

@test "--help exits 0" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --help
    [ "$status" -eq 0 ]
}

@test "--help output contains Usage:" {
    local output
    output=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Usage:"* ]]
}

@test "--version exits 0" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --version
    [ "$status" -eq 0 ]
}

@test "--version prints non-empty string" {
    local ver
    ver=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --version 2>&1)
    echo "version: ${ver}"
    [[ -n "${ver}" ]]
}

@test "unknown option exits non-zero" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --no-such-option
    [ "$status" -ne 0 ]
}

# ── Required-variable validation ──────────────────────────────────────────────

@test "exits non-zero when AWS_S3_BUCKET_NAME is unset" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e AWS_S3_BUCKET_NAME= \
        "${IMAGE}" /usr/local/bin/pg-volume-backup
    [ "$status" -ne 0 ]
}

@test "exits non-zero when no volumes found under BACKUP_ROOT" {
    local empty
    empty=$(mktemp -d)
    chmod o+rx "${empty}"
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e BACKUP_ROOT=/empty \
        -v "${empty}:/empty:ro" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup
    rm -rf "${empty}"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_HOST is missing and DB_VOLUME is set" {
    run run_pg_volume_backup \
        -e DB_VOLUME=vol \
        -e DB_HOST= \
        -e DB_NAME=mydb \
        -e DB_USER=myuser \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_NAME is missing and DB_VOLUME is set" {
    run run_pg_volume_backup \
        -e DB_VOLUME=vol \
        -e DB_HOST=dbhost \
        -e DB_NAME= \
        -e DB_USER=myuser \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_USER is missing and DB_VOLUME is set" {
    run run_pg_volume_backup \
        -e DB_VOLUME=vol \
        -e DB_HOST=dbhost \
        -e DB_NAME=mydb \
        -e DB_USER= \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

# ── Dry-run ───────────────────────────────────────────────────────────────────
# --dry-run is a pg-volume-backup argument, not a docker flag, so these tests
# call docker run directly rather than using run_pg_volume_backup (which
# places extra args before the image reference).

@test "--dry-run exits 0" {
    # shellcheck disable=SC2086
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e BACKUP_ROOT=/backup \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${TEST_TMPDIR}:/backup:ro" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --dry-run
    [ "$status" -eq 0 ]
}

@test "--dry-run produces no output files" {
    local outdir
    outdir=$(mktemp -d)
    chmod o+rwx "${outdir}"
    # shellcheck disable=SC2086
    docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e BACKUP_ROOT=/backup \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${TEST_TMPDIR}:/backup:ro" \
        -v "${outdir}:/output" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --dry-run > /dev/null
    local found
    found=$(find "${outdir}" -type f | head -1)
    rm -rf "${outdir}"
    echo "found: ${found}"
    [[ -z "${found}" ]]
}

@test "--dry-run logs dry-run mode message" {
    local output
    # shellcheck disable=SC2086
    output=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e BACKUP_ROOT=/backup \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${TEST_TMPDIR}:/backup:ro" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --dry-run 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"dry-run"* ]]
}
