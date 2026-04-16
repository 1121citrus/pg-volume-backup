# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-04-12

### Added

- Dockerfile: Alpine 3.22, non-root user (UID 10001), OCI labels,
  packages: aws-cli, bash, bzip2, bzip3, docker-cli, gnupg, gzip,
  lzop, pigz, postgresql-client, py3-cryptography, py3-urllib3, xz, zip
- `pg-volume-backup` CLI: volume discovery, pg_dump and raw-tar pipelines,
  SHA-256, compression (bzip2/gzip/xz/lzop/pigz/none), GPG symmetric
  encryption, `aws s3 mv` upload, `--dry-run` mode
- `startup`: container entrypoint — resolves `_FILE` secrets, writes `.env`,
  installs crontab, runs `crond -l 2 -f`
- `backup`: cron service script — sources `.env`, delegates to `pg-volume-backup`
- `healthcheck`: verifies `crond` running and crontab configured
- `common-functions`: shared logging helpers
- `build` script: lint → build → test → scan → advise → push
- Test suite (71 tests): CLI contracts, required-var validation, all
  compression modes, GPG encryption and decryption, archive naming and
  integrity, healthcheck scenarios, Dockerfile static analysis
- CI: `.github/workflows/ci.yml` using shared reusable workflows
- Release automation: `release-please` configuration
- Documentation: README, SECURITY, CONTRIBUTING, src/bin/README,
  test/README, test/TESTING
