#!/usr/bin/env bash
# shellcheck shell=bash

# test/staging-hooks.sh — repo-specific helpers and test implementations
# for the pg-volume-backup staging harness (test/staging).
#
# Called by: test/staging (generated) via `source staging-hooks.sh`
# Provides:  setup_hooks() — docker-run helpers
#            test_staging_* — repo-specific test functions
#
# The generated test/staging provides: scan/advise tests, setup(), run_tests(),
# main(). This file provides only what is repo-specific.

# ---------------------------------------------------------------------------
# setup_hooks — defines docker-run helpers used by test functions.
# Called by setup() in the generated harness after credentials are ready.
# Exported env vars from setup(): _aws_cfg_mount, _aws_creds_mount, _scan_tar
# ---------------------------------------------------------------------------
setup_hooks() {
    # Run pg-volume-backup with staging credentials and given CLI args.
    # Uses S3_BUCKET_NAME (set by --bucket) as AWS_S3_BUCKET_NAME inside the
    # container.  The binary is invoked directly (image uses CMD, not
    # ENTRYPOINT).
    run_pg_volume_backup() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run --rm ${DOCKER_RUN_ARGS:-} \
            -e "AWS_S3_BUCKET_NAME=${S3_BUCKET_NAME:-}" \
            -e "DRYRUN=${DRYRUN:-false}" \
            "${args[@]}" \
            "${IMAGE}" /usr/local/bin/pg-volume-backup "$@" 2>&1
    }

    # Run an aws CLI command inside the image, bypassing the service CMD.
    # Used for bucket setup/teardown in e2e tests.
    _aws() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run --rm --entrypoint /usr/bin/aws \
            ${DOCKER_RUN_ARGS:-} \
            "${args[@]}" \
            "${IMAGE}" "$@"
    }

    export -f run_pg_volume_backup _aws
}

# ---------------------------------------------------------------------------
# CLI smoke tests (no S3 connection required)
# ---------------------------------------------------------------------------

# test_staging_no_bucket — exits non-zero when AWS_S3_BUCKET_NAME is absent.
test_staging_no_bucket() {
    local result=0
    # shellcheck disable=SC2086
    docker run --rm ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" /usr/local/bin/pg-volume-backup \
        > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero without AWS_S3_BUCKET_NAME"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero" \
             "without AWS_S3_BUCKET_NAME"
        return 1
    fi
}

# test_staging_no_volumes — exits non-zero when BACKUP_ROOT has no volumes.
test_staging_no_volumes() {
    local tmpdir result=0
    tmpdir=$(mktemp -d /tmp/staging-novol-XXXXXX)
    chmod o+rx "${tmpdir}"

    # shellcheck disable=SC2086
    docker run --rm ${DOCKER_RUN_ARGS:-} \
        -e "AWS_S3_BUCKET_NAME=test-bucket" \
        -e "BACKUP_ROOT=/backup" \
        -v "${tmpdir}:/backup:ro" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup \
        > /dev/null 2>&1 || result=$?
    rm -rf "${tmpdir}"

    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero with empty BACKUP_ROOT"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero" \
             "with empty BACKUP_ROOT"
        return 1
    fi
}

# test_staging_dryrun — --dry-run with a synthetic volume exits 0, no S3 call.
test_staging_dryrun() {
    local tmpdir result=0 output
    tmpdir=$(mktemp -d /tmp/staging-dryrun-XXXXXX)
    mkdir -p "${tmpdir}/uploads"
    echo "test file" > "${tmpdir}/uploads/document.pdf"
    chmod -R o+rx "${tmpdir}"

    # shellcheck disable=SC2086
    output=$(docker run --rm ${DOCKER_RUN_ARGS:-} \
        -e "AWS_S3_BUCKET_NAME=test-bucket" \
        -e "BACKUP_ROOT=/backup" \
        -e "BACKUP_HOSTNAME=staging-test" \
        -v "${tmpdir}:/backup:ro" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup --dry-run \
        2>&1) || result=$?
    rm -rf "${tmpdir}"

    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': --dry-run exits 0 with synthetic volume"
    else
        echo "FAIL '${FUNCNAME[0]}': --dry-run exited non-zero (exit=${result})"
        printf '  -- output --\n' >&2
        printf '%s\n' "${output}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Cron service-mode tests
# ---------------------------------------------------------------------------

# test_staging_cron_dryrun — cron fires backup in service mode (dry-run).
#
# Overrides COMMAND to invoke pg-volume-backup with --dry-run so no S3 calls
# are made.  Sets CRON_EXPRESSION to every minute and polls logs up to 90s.
test_staging_cron_dryrun() {
    local tmpdir result=0
    tmpdir=$(mktemp -d /tmp/staging-cron-XXXXXX)
    mkdir -p "${tmpdir}/uploads"
    echo "test file" > "${tmpdir}/uploads/document.pdf"
    chmod -R o+rx "${tmpdir}"

    local cid
    # shellcheck disable=SC2086
    cid=$(docker run --detach \
        -e "AWS_S3_BUCKET_NAME=test-bucket" \
        -e "BACKUP_ROOT=/backup" \
        -e "BACKUP_HOSTNAME=staging-cron-test" \
        -e "CRON_EXPRESSION=* * * * *" \
        -e "COMMAND=/usr/local/bin/pg-volume-backup --dry-run" \
        -v "${tmpdir}:/backup:ro" \
        ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" 2>&1) || result=$?

    if [[ ${result} -ne 0 ]]; then
        rm -rf "${tmpdir}"
        echo "FAIL '${FUNCNAME[0]}': could not start container" \
             "(exit=${result})"
        return 1
    fi
    # shellcheck disable=SC2064
    trap "docker rm -f '${cid}' > /dev/null 2>&1 || true; \
          rm -rf '${tmpdir}'" RETURN

    local fired=false elapsed=0
    while [[ ${elapsed} -lt 90 ]]; do
        sleep 5
        elapsed=$(( elapsed + 5 ))
        if docker logs "${cid}" 2>&1 \
                | grep -q '\[INFO\].*finish pg-volume-backup'; then
            fired=true
            break
        fi
    done

    if "${fired}"; then
        echo "PASS '${FUNCNAME[0]}': cron fired backup in service" \
             "mode (dry-run)"
    else
        local logs
        logs=$(docker logs "${cid}" 2>&1)
        echo "FAIL '${FUNCNAME[0]}': cron did not fire within 90s"
        printf '  -- container logs --\n' >&2
        printf '%s\n' "${logs}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# End-to-end tests (require AWS credentials + s3:CreateBucket)
# ---------------------------------------------------------------------------

# test_staging_backup_e2e — backs up two synthetic volumes to a transient S3
# bucket and verifies 4 objects (2 archives + 2 checksums).
#
# Skips gracefully when s3:CreateBucket is unavailable.
test_staging_backup_e2e() {
    _aws_available || {
        _skip "AWS credentials not configured"
        return 0
    }

    local epoch test_bucket tmpdir
    epoch=$(date +%s)
    test_bucket="test.pg-volume-backup-${epoch}"
    tmpdir=$(mktemp -d /tmp/staging-e2e-XXXXXX)

    # shellcheck disable=SC2064
    trap "
        _aws s3 rb 's3://${test_bucket}' --force > /dev/null 2>&1 || true
        rm -rf '${tmpdir}'
    " RETURN

    printf '  creating transient test bucket s3://%s...\n' \
        "${test_bucket}" >&2
    _aws s3 mb "s3://${test_bucket}" > /dev/null 2>&1 || {
        _skip "s3:CreateBucket not available on test.pg-volume-backup-*"
        return 0
    }

    mkdir -p "${tmpdir}/uploads" "${tmpdir}/data"
    echo "fake-pdf-content" > "${tmpdir}/uploads/document.pdf"
    echo "fake-data"        > "${tmpdir}/data/file.dat"
    chmod -R o+rx "${tmpdir}"

    local aws_mounts=()
    _append_aws_mounts aws_mounts

    printf '  running backup to s3://%s...\n' "${test_bucket}" >&2
    local bk_output bk_result=0
    # shellcheck disable=SC2086
    bk_output=$(docker run --rm ${DOCKER_RUN_ARGS:-} \
        -e "AWS_S3_BUCKET_NAME=${test_bucket}" \
        -e "BACKUP_ROOT=/backup" \
        -e "BACKUP_HOSTNAME=staging-test" \
        -e "COMPRESSION=none" \
        -v "${tmpdir}:/backup:ro" \
        "${aws_mounts[@]}" \
        "${IMAGE}" /usr/local/bin/pg-volume-backup 2>&1) || bk_result=$?

    if [[ ${bk_result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': pg-volume-backup exited" \
             "non-zero (${bk_result})"
        printf '  -- output --\n' >&2
        printf '%s\n' "${bk_output}" >&2
        return 1
    fi

    local count=0
    count=$(_aws s3 ls --recursive "s3://${test_bucket}/" \
                2>/dev/null | wc -l | tr -d ' ')

    if [[ "${count}" -eq 4 ]]; then
        echo "PASS '${FUNCNAME[0]}': ${count} objects in S3" \
             "(2 archives + 2 checksums for 2 volumes)"
    else
        echo "FAIL '${FUNCNAME[0]}': ${count} objects in S3 (expected 4)"
        printf 'Objects in bucket:\n' >&2
        _aws s3 ls --recursive "s3://${test_bucket}/" >&2 2>&1 || true
        printf 'Backup output:\n' >&2
        printf '%s\n' "${bk_output}" >&2
        return 1
    fi
}

# test_staging_cron_backup_e2e — end-to-end backup correctness via cron
# service mode.
#
# Creates a disposable bucket, starts the container with CRON_EXPRESSION=
# every minute, polls 90s for the first cron tick, then verifies 4 objects.
# Skips gracefully when s3:CreateBucket is unavailable.
test_staging_cron_backup_e2e() {
    _aws_available || {
        _skip "AWS credentials not configured"
        return 0
    }

    local epoch test_bucket tmpdir
    epoch=$(date +%s)
    test_bucket="test.pg-volume-backup-${epoch}"
    tmpdir=$(mktemp -d /tmp/staging-cron-e2e-XXXXXX)

    # shellcheck disable=SC2064
    trap "
        _aws s3 rb 's3://${test_bucket}' --force > /dev/null 2>&1 || true
        rm -rf '${tmpdir}'
    " RETURN

    printf '  creating transient test bucket s3://%s...\n' \
        "${test_bucket}" >&2
    _aws s3 mb "s3://${test_bucket}" > /dev/null 2>&1 || {
        _skip "s3:CreateBucket not available on test.pg-volume-backup-*"
        return 0
    }

    mkdir -p "${tmpdir}/uploads" "${tmpdir}/data"
    echo "fake-pdf-content" > "${tmpdir}/uploads/document.pdf"
    echo "fake-data"        > "${tmpdir}/data/file.dat"
    chmod -R o+rx "${tmpdir}"

    local aws_mounts=()
    _append_aws_mounts aws_mounts

    printf '  starting service container (cron every minute)...\n' >&2
    local cid cid_result=0
    # shellcheck disable=SC2086
    cid=$(docker run --detach \
        -e "AWS_S3_BUCKET_NAME=${test_bucket}" \
        -e "BACKUP_ROOT=/backup" \
        -e "BACKUP_HOSTNAME=staging-cron-test" \
        -e "CRON_EXPRESSION=* * * * *" \
        -e "COMPRESSION=none" \
        -v "${tmpdir}:/backup:ro" \
        "${aws_mounts[@]}" \
        ${DOCKER_RUN_ARGS:-} \
        "${IMAGE}" 2>&1) || cid_result=$?
    if [[ ${cid_result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': could not start container" \
             "(exit=${cid_result})"
        return 1
    fi

    # Extend trap to also remove the container.
    # shellcheck disable=SC2064
    trap "
        docker rm -f '${cid}' > /dev/null 2>&1 || true
        _aws s3 rb 's3://${test_bucket}' --force > /dev/null 2>&1 || true
        rm -rf '${tmpdir}'
    " RETURN

    printf '  waiting for first cron tick (up to 90s)...\n' >&2
    local fired=false elapsed=0
    while [[ ${elapsed} -lt 90 ]]; do
        sleep 5
        elapsed=$(( elapsed + 5 ))
        if docker logs "${cid}" 2>&1 \
                | grep -q '\[INFO\].*finish backup'; then
            fired=true
            break
        fi
    done

    if ! "${fired}"; then
        local logs
        logs=$(docker logs "${cid}" 2>&1)
        echo "FAIL '${FUNCNAME[0]}': cron did not fire within 90s"
        printf '  -- container logs --\n' >&2
        printf '%s\n' "${logs}" >&2
        return 1
    fi

    local count=0
    count=$(_aws s3 ls --recursive "s3://${test_bucket}/" \
                2>/dev/null | wc -l | tr -d ' ')

    if [[ "${count}" -eq 4 ]]; then
        echo "PASS '${FUNCNAME[0]}': ${count} objects in S3 after" \
             "cron backup (2 archives + 2 checksums for 2 volumes)"
    else
        local bk_logs
        bk_logs=$(docker logs "${cid}" 2>&1)
        echo "FAIL '${FUNCNAME[0]}': ${count} objects in S3 (expected 4)"
        printf 'Objects in bucket:\n' >&2
        _aws s3 ls --recursive "s3://${test_bucket}/" >&2 2>&1 || true
        printf 'Container logs:\n' >&2
        printf '%s\n' "${bk_logs}" >&2
        return 1
    fi
}
