#!/usr/bin/env bats
# test/03-backup-required-vars.bats — test required-variable validation via backup.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pg-volume-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup

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

@test "exits non-zero when AWS_S3_BUCKET_NAME is unset" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME= \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_HOST is missing and DB_VOLUME is set" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e DB_VOLUME=vol \
        -e DB_HOST= \
        -e DB_NAME=mydb \
        -e DB_USER=myuser \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_NAME is missing and DB_VOLUME is set" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e DB_VOLUME=vol \
        -e DB_HOST=dbhost \
        -e DB_NAME= \
        -e DB_USER=myuser \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}

@test "exits non-zero when DB_USER is missing and DB_VOLUME is set" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e DB_VOLUME=vol \
        -e DB_HOST=dbhost \
        -e DB_NAME=mydb \
        -e DB_USER= \
        -e BACKUP_ROOT=/backup \
        -v "${TEST_TMPDIR}:/backup:ro"
    [ "$status" -ne 0 ]
}
