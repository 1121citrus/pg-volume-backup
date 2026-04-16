# Testing

## Overview

The test suite is split into two tiers:

| Tier | Scripts | Requires | Run by |
| --- | --- | --- | --- |
| Automated | `run-all` and its constituent scripts | Docker only | `./build` |
| Manual integration | `staging` | Real S3 credentials | Developer |

---

## Automated tests (`test/run-all`)

`run-all` is the CI-suitable suite.  It is invoked automatically by `./build`
during stage 3 and requires nothing beyond a local Docker daemon.  All AWS
interaction is replaced by the stub at `test/bin/aws`.

### Constituent test scripts

| Script | What it tests |
| --- | --- |
| `01-build.bats` | `build` option parsing for `--advice` alias and `--cache`; `staging --help` coverage for `--scan`/`--advise` |
| `02-pg-volume-backup.bats` | CLI option parsing (`--help`, `--version`, unknown option); required-variable validation (`AWS_S3_BUCKET_NAME`, `DB_HOST`/`DB_NAME`/`DB_USER` when `DB_VOLUME` is set, no volumes under `BACKUP_ROOT`) |
| `03-backup-required-vars.bats` | `backup` script rejects missing `AWS_S3_BUCKET_NAME` and missing DB vars when `DB_VOLUME` is set |
| `04-backup-success.bats` | Archive naming (volume name, hostname, timestamp pattern); SHA-256 companion file (presence, `.tar.sha256` extension, valid hash line); all five compression modes; invalid compression exits non-zero; archive is a valid tar containing the backed-up file |
| `05-backup-encryption.bats` | GPG encryption applied when `GPG_PASSPHRASE` or `GPG_PASSPHRASE_FILE` is set; skipped when neither is configured; passphrase with spaces works; encrypted output decrypts correctly |
| `06-healthcheck.bats` | `healthcheck` exits non-zero when `crond` is absent or crontab is missing; exits zero when both are present |
| `07-image-metadata.bats` | Dockerfile static analysis: `ARG VERSION/GIT_COMMIT/BUILD_DATE` declared; all OCI labels present and wired to build args; `USER` directive present |

### Running

```console
# Via the build script (recommended — also lints, builds, and scans)
./build --no-scan

# Directly, against a specific image
IMAGE=1121citrus/pg-volume-backup:dev-abc1234 test/run-all
```

The `IMAGE` environment variable selects which image to test.  When omitted,
`test/run-all` defaults to `1121citrus/pg-volume-backup:latest`.  `./build`
always sets `IMAGE` to the image it just built.

### Test stubs (`test/bin/`)

| Stub | Replaces | Behavior |
| --- | --- | --- |
| `aws` | AWS CLI | Copies the uploaded file to `/output` if that path is mounted; otherwise no-ops |

### Test fixtures (`test/fixtures/`)

| File | Used by | Purpose |
| --- | --- | --- |
| `gpg-passphrase` | `05-backup-encryption.bats` | Fixed passphrase for `GPG_PASSPHRASE_FILE` tests |

---

## Manual integration tests (`test/staging`)

`test/staging` exercises the full backup pipeline with a real S3 bucket.  It
is **not** part of `run-all` and is never run in CI.

Run it manually before tagging a release.

### Required environment

| Variable | Required for | Notes |
| --- | --- | --- |
| `IMAGE` | All tests | Image to test; defaults to `1121citrus/pg-volume-backup:latest` |
| `AWS_S3_BUCKET_NAME` | Service tests | S3 bucket; omit to run only switch-independent tests |
| `AWS_CONFIG_FILE` | Service tests | Path to AWS config file |
| `AWS_ACCESS_KEY_ID` | Service tests | AWS access key; use instead of config file |
| `AWS_SECRET_ACCESS_KEY` | Service tests | AWS secret key (required with `AWS_ACCESS_KEY_ID`) |
| `AWS_DRYRUN` | Service tests | Set to `false` for real S3 writes; defaults to `true` |
| `STAGING_SCAN` | Scanner phase | `true`/`false`; controls Trivy scan (default: `true`) |
| `STAGING_ADVISE` | Scanner phase | `true`/`false`; controls Grype advisement (default: `true`) |

### Staging scanner options

`test/staging` supports the same scanner controls as `build`:

- `--scan` / `--no-scan`
- `--advise [grype,scout,dive,all]`
- `--no-advise`

### Running

```console
# Switch-independent tests only (help, version, option validation)
IMAGE=1121citrus/pg-volume-backup:1.2.3 test/staging

# Full suite with real S3
IMAGE=1121citrus/pg-volume-backup:1.2.3 \
  AWS_S3_BUCKET_NAME=staging.backups \
  AWS_CONFIG_FILE=~/.aws/config \
  test/staging
```

Tests that require `AWS_S3_BUCKET_NAME` or credentials print `SKIP` (not
`FAIL`) when those values are absent, so the script always exits cleanly in a
credentials-free environment.
