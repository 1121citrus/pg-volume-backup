#!/usr/bin/env bats
# test/05-backup-encryption.bats — test GPG encryption paths in src/bin/backup.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pg-volume-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Create a temp backup-root with one volume directory.
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "${TEST_TMPDIR}/backup/testvol"
    echo "test content" > "${TEST_TMPDIR}/backup/testvol/data.txt"
    mkdir -p "${TEST_TMPDIR}/output"
    chmod -R o+rwx "${TEST_TMPDIR}"
    export TEST_TMPDIR

    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e AWS_S3_BUCKET_NAME=test-bucket \
            -e BACKUP_ROOT=/backup \
            -e COMPRESSION=none \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${TEST_TMPDIR}/backup:/backup:ro" \
            -v "${TEST_TMPDIR}/output:/output" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

teardown() {
    if [ -n "${TEST_TMPDIR:-}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}

@test "GPG encrypts when GPG_PASSPHRASE env var is set" {
    local output
    output=$(run_backup -e GPG_PASSPHRASE=test-passphrase)
    echo "output: ${output}"
    [[ "${output}" == *"encrypt"* ]]
}

@test "GPG-encrypted archive has .gpg extension" {
    run_backup -e GPG_PASSPHRASE=test-passphrase > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.gpg" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "GPG encrypts when passphrase contains spaces" {
    local output
    output=$(run_backup -e "GPG_PASSPHRASE=pass phrase with spaces")
    echo "output: ${output}"
    [[ "${output}" == *"encrypt"* ]]
}

@test "GPG encrypts when GPG_PASSPHRASE_FILE is readable" {
    local output
    output=$(run_backup \
        -e GPG_PASSPHRASE= \
        -e GPG_PASSPHRASE_FILE=/test/fixtures/gpg-passphrase)
    echo "output: ${output}"
    [[ "${output}" == *"encrypt"* ]]
}

@test "no GPG encryption when no passphrase is available" {
    local output
    output=$(run_backup \
        -e GPG_PASSPHRASE= \
        -e GPG_PASSPHRASE_FILE=/nonexistent)
    echo "output: ${output}"
    [[ "${output}" != *"encrypt"* ]]
}

@test "no .gpg file produced when no passphrase is configured" {
    run_backup -e GPG_PASSPHRASE= -e GPG_PASSPHRASE_FILE=/nonexistent > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.gpg" | head -1)
    echo "found: ${found}"
    [[ -z "${found}" ]]
}

@test "GPG-encrypted output decrypts with the passphrase" {
    run_backup -e GPG_PASSPHRASE=test-passphrase > /dev/null
    local gpgfile
    gpgfile=$(find "${TEST_TMPDIR}/output" -name "*.gpg" | head -1)
    echo "gpgfile: ${gpgfile}"
    gpg --batch --yes \
        --passphrase test-passphrase \
        --pinentry-mode loopback \
        --decrypt "${gpgfile}" > /dev/null
}
