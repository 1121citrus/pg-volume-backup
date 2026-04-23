#!/usr/bin/env bats
# test/06-healthcheck.bats — test all healthcheck scenarios.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    IMAGE="${IMAGE:-1121citrus/pg-volume-backup:latest}"
    export IMAGE

    run_healthcheck() {
        local script=$1; shift
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            --entrypoint /usr/bin/env \
            "$@" \
            "${IMAGE}" \
            bash -c "${script}" > /dev/null 2>&1
    }
    export -f run_healthcheck
}

@test "healthcheck exits non-zero when supercronic is absent" {
    run run_healthcheck "/usr/local/bin/healthcheck"
    [ "$status" -ne 0 ]
}

@test "healthcheck exits 0 with supercronic running and crontab configured" {
    local script
    script='mkdir -p /var/spool/cron/crontabs'
    script+=' && printf "%s\n" "* * * * * /usr/local/bin/backup 2>&1"'
    script+=' > /var/spool/cron/crontabs/$(id -un)'
    script+=' && chmod 0600 /var/spool/cron/crontabs/$(id -un)'
    script+=' && { supercronic /var/spool/cron/crontabs/$(id -un) & sleep 0.5; }'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}" \
        --tmpfs /var/spool/cron/crontabs:uid=10001,gid=10001,mode=0700
    [ "$status" -eq 0 ]
}

@test "healthcheck exits non-zero when crontab is missing" {
    local script
    script='supercronic /var/spool/cron/crontabs/$(id -un) & sleep 0.5'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}"
    [ "$status" -ne 0 ]
}
