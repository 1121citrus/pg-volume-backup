#!/usr/bin/env bats
# test/04-backup-success.bats — test successful raw-volume backup paths.
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
            -e BACKUP_HOSTNAME=testhost \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
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

# ── Basic success ─────────────────────────────────────────────────────────────

@test "no-compression backup begins and finishes" {
    local output
    output=$(run_backup -e COMPRESSION=none)
    echo "output: ${output}"
    [[ "${output}" == *"begin backup"* ]]
    [[ "${output}" == *"finish backup"* ]]
}

# ── Archive naming ────────────────────────────────────────────────────────────

@test "archive name contains volume name" {
    run_backup -e COMPRESSION=none > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*-testvol-backup*" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "archive name contains hostname" {
    run_backup -e COMPRESSION=none > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*-testhost-*" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "archive name matches timestamp pattern" {
    run_backup -e COMPRESSION=none > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" \
        -name "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]-*" \
        | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

# ── SHA256 companion ──────────────────────────────────────────────────────────

@test "SHA256 companion file is created alongside archive" {
    run_backup -e COMPRESSION=none > /dev/null
    local sha_file
    sha_file=$(find "${TEST_TMPDIR}/output" -name "*.sha256" | head -1)
    echo "sha_file: ${sha_file}"
    [[ -n "${sha_file}" ]]
}

@test "SHA256 companion file has .tar.sha256 extension" {
    run_backup -e COMPRESSION=none > /dev/null
    local sha_file
    sha_file=$(find "${TEST_TMPDIR}/output" -name "*.tar.sha256" | head -1)
    echo "sha_file: ${sha_file}"
    [[ -n "${sha_file}" ]]
}

@test "SHA256 companion contains a valid sha256 hash line" {
    run_backup -e COMPRESSION=none > /dev/null
    local sha_file
    sha_file=$(find "${TEST_TMPDIR}/output" -name "*.tar.sha256" | head -1)
    echo "sha_file: ${sha_file}"
    local contents
    contents=$(cat "${sha_file}")
    echo "contents: ${contents}"
    [[ "${contents}" =~ ^[0-9a-f]{64}[[:space:]] ]]
}

# ── Compression ───────────────────────────────────────────────────────────────

@test "bzip2 compression produces .tar.bz2 archive" {
    run_backup -e COMPRESSION=bzip2 > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.tar.bz2" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "gzip compression produces .tar.gz archive" {
    run_backup -e COMPRESSION=gzip > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.tar.gz" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "xz compression produces .tar.xz archive" {
    run_backup -e COMPRESSION=xz > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.tar.xz" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "pigz compression produces .tar.gz archive" {
    run_backup -e COMPRESSION=pigz > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.tar.gz" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "lzop compression produces .tar.lzo archive" {
    run_backup -e COMPRESSION=lzop > /dev/null
    local found
    found=$(find "${TEST_TMPDIR}/output" -name "*.tar.lzo" | head -1)
    echo "found: ${found}"
    [[ -n "${found}" ]]
}

@test "exits non-zero for unsupported compression algorithm" {
    run run_backup -e COMPRESSION=invalid
    [ "$status" -ne 0 ]
}

# ── Archive integrity ─────────────────────────────────────────────────────────

@test "no-compression archive is a valid tar file" {
    run_backup -e COMPRESSION=none > /dev/null
    local tarfile
    tarfile=$(find "${TEST_TMPDIR}/output" -name "*.tar" | head -1)
    echo "tarfile: ${tarfile}"
    tar -tf "${tarfile}" > /dev/null
}

@test "archive contains backed-up file" {
    run_backup -e COMPRESSION=none > /dev/null
    local tarfile
    tarfile=$(find "${TEST_TMPDIR}/output" -name "*.tar" | head -1)
    local contents
    contents=$(tar -tf "${tarfile}")
    echo "contents: ${contents}"
    echo "${contents}" | grep -q 'data.txt'
}
