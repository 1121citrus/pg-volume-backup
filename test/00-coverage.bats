#!/usr/bin/env bats
# test/00-coverage.bats — direct-execution unit tests for kcov coverage.
#
# These tests invoke src/ scripts directly (not inside Docker) so that
# kcov can instrument them.  Stubs for external binaries (aws, crond,
# pg_dump, pidof, pgrep) are written into a temp bin dir prepended to
# PATH before each test.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    # Install common-functions where the source statements expect it.
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions

    # Install the version file expected by pg-volume-backup.
    mkdir -p /usr/local/share/pg-volume-backup
    printf '%s\n' "dev" > /usr/local/share/pg-volume-backup/version

    # Create crontab directory (required by startup and healthcheck).
    mkdir -p /var/spool/cron/crontabs

    # Workspace: a backup root with one volume directory.
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "${TEST_TMPDIR}/backup/testvol"
    printf '%s\n' "test content" \
        > "${TEST_TMPDIR}/backup/testvol/data.txt"

    # Stub directory: these stubs shadow real binaries via PATH.
    STUB_DIR="${TEST_TMPDIR}/stubs"
    mkdir -p "${STUB_DIR}"

    # aws stub: no-op (real aws is not available / no credentials needed).
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'exit 0' \
        > "${STUB_DIR}/aws"
    chmod +x "${STUB_DIR}/aws"

    # pg_dump stub: emits a minimal SQL header.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "-- pg_dump stub"' \
        > "${STUB_DIR}/pg_dump"
    chmod +x "${STUB_DIR}/pg_dump"

    # crond stub: exits 0 immediately (startup exec-replaces with it).
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'exit 0' \
        > "${STUB_DIR}/crond"
    chmod +x "${STUB_DIR}/crond"

    # pidof stub: succeeds only when asked for "crond".
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '[[ "${1:-}" == "crond" ]] && exit 0' \
        'exit 1' \
        > "${STUB_DIR}/pidof"
    chmod +x "${STUB_DIR}/pidof"

    # pgrep stub: succeeds for "pgrep -x crond".
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '[[ "${1:-}" == "-x" && "${2:-}" == "crond" ]] && exit 0' \
        'exit 1' \
        > "${STUB_DIR}/pgrep"
    chmod +x "${STUB_DIR}/pgrep"

    # Write a crontab for healthcheck tests that look for the default COMMAND.
    local _user
    _user=$(id -un)
    printf '%s\n' "@daily /usr/local/bin/backup 2>&1" \
        > "/var/spool/cron/crontabs/${_user}"

    export PATH="${STUB_DIR}:${PATH}"
    export AWS_S3_BUCKET_NAME=test-bucket
    export BACKUP_ROOT="${TEST_TMPDIR}/backup"
    export BACKUP_HOSTNAME=testhost
    export COMPRESSION=none
    export DEBUG=false
    export ENV="${TEST_TMPDIR}/.env"
    export REPO_ROOT TEST_TMPDIR STUB_DIR
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── common-functions ──────────────────────────────────────────────────────────

@test "common-functions: is_true accepts 'true'" {
    # shellcheck disable=SC1091
    source /usr/local/include/bash/common-functions
    is_true true
}

@test "common-functions: is_true accepts '1'" {
    # shellcheck disable=SC1091
    source /usr/local/include/bash/common-functions
    is_true 1
}

@test "common-functions: is_true accepts 'yes'" {
    # shellcheck disable=SC1091
    source /usr/local/include/bash/common-functions
    is_true yes
}

@test "common-functions: is_true rejects 'false'" {
    # shellcheck disable=SC1091
    source /usr/local/include/bash/common-functions
    ! is_true false
}

@test "common-functions: is_true rejects '0'" {
    # shellcheck disable=SC1091
    source /usr/local/include/bash/common-functions
    ! is_true 0
}

# ── pg-volume-backup ──────────────────────────────────────────────────────────

@test "pg-volume-backup: --help exits 0" {
    run bash "${REPO_ROOT}/src/bin/pg-volume-backup" --help
    [ "$status" -eq 0 ]
}

@test "pg-volume-backup: --help output contains Usage:" {
    local output
    output=$(bash "${REPO_ROOT}/src/bin/pg-volume-backup" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Usage:"* ]]
}

@test "pg-volume-backup: --version exits 0" {
    run bash "${REPO_ROOT}/src/bin/pg-volume-backup" --version
    [ "$status" -eq 0 ]
}

@test "pg-volume-backup: --version prints non-empty string" {
    local ver
    ver=$(bash "${REPO_ROOT}/src/bin/pg-volume-backup" --version 2>&1)
    echo "version: ${ver}"
    [[ -n "${ver}" ]]
}

@test "pg-volume-backup: unknown option exits non-zero" {
    run bash "${REPO_ROOT}/src/bin/pg-volume-backup" --no-such-option
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: missing AWS_S3_BUCKET_NAME exits non-zero" {
    run env -u AWS_S3_BUCKET_NAME \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: empty BACKUP_ROOT exits non-zero" {
    local empty_root
    empty_root="${TEST_TMPDIR}/empty"
    mkdir -p "${empty_root}"
    run env BACKUP_ROOT="${empty_root}" \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: --dry-run exits 0" {
    run bash "${REPO_ROOT}/src/bin/pg-volume-backup" --dry-run
    [ "$status" -eq 0 ]
}

@test "pg-volume-backup: --dry-run logs dry-run message" {
    local output
    output=$(bash "${REPO_ROOT}/src/bin/pg-volume-backup" --dry-run 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"dry-run"* ]]
}

@test "pg-volume-backup: dry-run logs begin and finish" {
    local output
    output=$(bash "${REPO_ROOT}/src/bin/pg-volume-backup" --dry-run 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"begin pg-volume-backup"* ]]
    [[ "${output}" == *"finish pg-volume-backup"* ]]
}

@test "pg-volume-backup: non-dry-run backup completes" {
    local output
    output=$(bash "${REPO_ROOT}/src/bin/pg-volume-backup" 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"finish pg-volume-backup"* ]]
}

@test "pg-volume-backup: DB_VOLUME set without DB_HOST exits non-zero" {
    run env DB_VOLUME=testvol DB_HOST= DB_NAME=mydb DB_USER=myuser \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: DB_VOLUME set without DB_NAME exits non-zero" {
    run env DB_VOLUME=testvol DB_HOST=dbhost DB_NAME= DB_USER=myuser \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: DB_VOLUME set without DB_USER exits non-zero" {
    run env DB_VOLUME=testvol DB_HOST=dbhost DB_NAME=mydb DB_USER= \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

@test "pg-volume-backup: DB_VOLUME dry-run pg_dump path logs pg_dump" {
    local output
    output=$(env DB_VOLUME=testvol DB_HOST=dbhost DB_NAME=mydb DB_USER=myuser \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup" --dry-run 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"pg_dump"* ]]
}

@test "pg-volume-backup: unknown compression exits non-zero" {
    run env COMPRESSION=invalid \
        bash "${REPO_ROOT}/src/bin/pg-volume-backup"
    [ "$status" -ne 0 ]
}

# ── startup ───────────────────────────────────────────────────────────────────

@test "startup: creates env file at ENV path" {
    run bash "${REPO_ROOT}/src/bin/startup"
    [ "$status" -eq 0 ]
    [ -f "${ENV}" ]
}

@test "startup: env file contains AWS_S3_BUCKET_NAME" {
    bash "${REPO_ROOT}/src/bin/startup" 2>/dev/null || true
    local contents
    contents=$(cat "${ENV}")
    echo "contents: ${contents}"
    [[ "${contents}" == *"AWS_S3_BUCKET_NAME"* ]]
}

@test "startup: installs crontab containing COMMAND" {
    bash "${REPO_ROOT}/src/bin/startup" 2>/dev/null || true
    local crontab_path
    crontab_path="/var/spool/cron/crontabs/$(id -un)"
    local contents
    contents=$(cat "${crontab_path}")
    echo "contents: ${contents}"
    [[ "${contents}" == *"/usr/local/bin/backup"* ]]
}

@test "startup: exits 0" {
    run bash "${REPO_ROOT}/src/bin/startup"
    [ "$status" -eq 0 ]
}

# ── healthcheck ───────────────────────────────────────────────────────────────

@test "healthcheck: exits 0 when crond running and crontab correct" {
    run bash "${REPO_ROOT}/src/bin/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits 1 when crond is not running" {
    # Override stubs so pidof and pgrep both exit 1.
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' \
        > "${STUB_DIR}/pidof"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' \
        > "${STUB_DIR}/pgrep"
    run bash "${REPO_ROOT}/src/bin/healthcheck"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"crond is not running"* ]]
}

@test "healthcheck: exits 1 when crontab does not contain COMMAND" {
    local _user
    _user=$(id -un)
    # Write a crontab that does NOT contain the expected command.
    printf '%s\n' "@daily /some/other/command 2>&1" \
        > "/var/spool/cron/crontabs/${_user}"
    run bash "${REPO_ROOT}/src/bin/healthcheck"
    [ "$status" -eq 1 ]
    [[ "${output}" == *"missing"* ]]
}

# ── backup ────────────────────────────────────────────────────────────────────

@test "backup: exits 0 with valid environment" {
    run bash "${REPO_ROOT}/src/bin/backup"
    [ "$status" -eq 0 ]
}

@test "backup: logs begin and finish" {
    local output
    output=$(bash "${REPO_ROOT}/src/bin/backup" 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"begin backup"* ]]
    [[ "${output}" == *"finish backup"* ]]
}
