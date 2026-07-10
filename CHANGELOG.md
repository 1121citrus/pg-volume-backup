# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.10] - 2026-07-10

### Fixed

- Eliminate the inherited `supercronic` Go stdlib scan finding by building the
  binary from source in the child image

### Changed

- Keep the child image on the shared `aws-backup-base` runtime while replacing
  the inherited `supercronic` binary with a source-built copy

## [1.0.9] - 2026-07-10

### Fixed

- Remove temporary `urllib3` Trivy suppressions that were tied to the retired
  child-image Python overlay
- Update `SECURITY.md` scanner posture notes to match the current base-inherited
  finding model and release-readiness checks

### Changed

- Build the Docker CLI from source (`docker/cli` v29.6.1 with Go 1.26.5) in a
  dedicated builder stage instead of copying it from the prebuilt `docker:cli`
  image
- Drop child-image Python package overlay logic (`python3-pip`, `idna`,
  `urllib3`) and rely on the shared `awscli-2` runtime from `aws-backup-base`

## [1.0.8] - 2026-06-09

### Fixed

- Suppress newly surfaced unfixable AL2023 HIGH CVEs in `.trivyignore` for
  local staging and CI Trivy gates
- Update security triage documentation to reflect current AL2023 package
  availability constraints and temporary suppression policy

### Changed

- Refine `build` advisory tooling: pin `scc` image tag to `v3.7.0`, call `scc`
  explicitly, simplify `test/run-all` env invocation, and replace the
  code-maat churn stage with a git+awk churn summary

## [1.0.7] - 2026-06-09

### Fixed

- Restore targeted Trivy suppressions for GitHub CI builds that still consume a
  published `aws-backup-base:latest` image lagging behind the rebuilt local base
- Document scanner and CVE triage status, including the distinction between
  local rebuilt-base validation and published-base CI behavior

### Added

- Add metrics, security, and churn advisory stages to the `build` pipeline

### Changed

- Bump `actions/checkout` from `6.0.2` to `6.0.3`
- Bump `shared-github-workflows` pin to `65524d3e65ab`

## [1.0.6] - 2026-05-04

### Fixed

- Auto-detect `.trivyignore` in staging Trivy scan: `_TRIVY_IGNOREFILE` defaulted
  to empty; now defaults to `.trivyignore`, matching `build` auto-detection
- Suppress unfixable AL2023 CVEs in `build` scan: conditionally mount `.trivyignore`
  and pass `--ignorefile` when present; add entries for CVE-2026-4046 (glibc) and
  CVE-2026-3644, CVE-2026-4786, CVE-2026-6100 (python3/cpython)

### Added

- Add `gitleaks` CI workflow for secret scanning
- Regenerate `build` and `test/staging` scripts with gitleaks advisement support
  and dive output filter

## [1.0.5] - 2026-05-01

### Fixed

- Mount `.trivyignore` into the Trivy container (`build` and
  `test/staging`) so unfixed AL2023 CVEs are suppressed correctly;
  without the mount the ignore file was silently skipped and the
  gating scan failed
- Add `.trivyignore` entries for CVE-2026-4046 (glibc) and
  CVE-2026-3644, CVE-2026-4786, CVE-2026-6100 (python3/cpython) —
  fix versions identified by Trivy but not yet available in the
  AL2023 package repositories

## [1.0.4] - 2026-04-27

### Changed

- Migrate base image from Alpine to Amazon Linux 2023 (AL2023); replace
  `apk` with `dnf`; switch runtime packages to AL2023 equivalents
- Bump `shared-github-workflows` CI SHA pin to `b06a3294`
- Switch Dependabot schedule from weekly to daily; update Docker ecosystem
  comment to reflect `docker:cli` builder stage (not Alpine base)
- Bump Alpine 3.22 → 3.23 (captured before AL2023 migration)

### Added

- Staging test: add `--dryrun`, `--advise`, and `--cache` options

## [1.0.3] - 2026-04-26

### Notes

See git log for details.

## [1.0.2] - 2026-04-26

### Notes

See git log for details.

## [1.0.1] - 2026-04-25

### Notes

See git log for details.

## [1.0.0] - 2026-04-12

### Notes

See git log for details.

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

[Unreleased]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.8...HEAD
[1.0.8]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/1121citrus/pg-volume-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/1121citrus/pg-volume-backup/compare/v0.0.1...v1.0.0
[0.0.1]: https://github.com/1121citrus/pg-volume-backup/releases/tag/v0.0.1
