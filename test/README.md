# test — pg-volume-backup test suite

For detailed test documentation see **[TESTING.md](TESTING.md)**.

## Quick start

```sh
# Run the full automated suite via the build script:
./build --no-scan

# Run the automated suite directly:
IMAGE=1121citrus/pg-volume-backup:dev-abc1234 test/run-all

# Pre-release staging (requires real S3 credentials):
IMAGE=1121citrus/pg-volume-backup:1.2.3 \
  AWS_S3_BUCKET_NAME=my-staging-bucket \
  AWS_CONFIG_FILE=~/.aws/config \
  test/staging
```

## Structure

| Path | Purpose |
| --- | --- |
| `run-all` | Runner — executes all automated tests |
| `01-build.bats` | `build` and `staging` script option parsing |
| `02-pg-volume-backup.bats` | CLI option parsing and required-variable validation |
| `03-backup-required-vars.bats` | Required-variable validation via the `backup` script |
| `04-backup-success.bats` | Successful raw-volume backup across all compression modes |
| `05-backup-encryption.bats` | GPG encryption paths |
| `06-healthcheck.bats` | Container health check scenarios |
| `07-image-metadata.bats` | Dockerfile static analysis (OCI labels, build args) |
| `staging` | Manual pre-release end-to-end tests (real S3) |
| `bin/` | Test stubs (`aws`) |
| `fixtures/` | Static data used by tests |
| `TESTING.md` | Full test documentation |
