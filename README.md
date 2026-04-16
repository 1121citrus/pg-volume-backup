# 1121citrus/pg-volume-backup

Back up Docker volumes and PostgreSQL databases to S3.

## Synopsis

`pg-volume-backup` backs up named Docker volumes and PostgreSQL databases to
an S3 bucket on a configurable schedule.  Each volume produces its own
timestamped archive, optionally compressed and GPG-encrypted.  A SHA-256
checksum companion file is created alongside each archive for integrity
verification.

Designed to work alongside
[1121citrus/rotate-aws-backups](https://github.com/1121citrus/rotate-aws-backups)
for retention management.

## Quick start

```yaml
services:
  backup:
    image: 1121citrus/pg-volume-backup:latest
    environment:
      AWS_S3_BUCKET_NAME: my-backup-bucket
      CRON_EXPRESSION: "@daily"
      COMPRESSION: gzip
      # Database backup
      DB_HOST: db
      DB_NAME: myapp
      DB_USER: backup
      DB_VOLUME: db-data
    secrets:
      - aws-config
      - aws-credentials
      - db-password
      - gpg-passphrase
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - app-data:/backup/app-data
      - db-data:/backup/db-data

secrets:
  aws-config:
    file: .secrets/aws-config
  aws-credentials:
    file: .secrets/aws-credentials
  db-password:
    file: .secrets/db-password
  gpg-passphrase:
    file: .secrets/gpg-passphrase
```

## How it works

### Volume discovery

Every subdirectory of `BACKUP_ROOT` (default `/backup`) is treated as one
backup target.  Mount each Docker volume you want to back up as
`/backup/<volume-name>`.

### Two backup pipelines

**PostgreSQL volumes** — when `DB_VOLUME` names a volume, that volume is
backed up with `pg_dump` over the internal Docker network rather than by
tarring the raw data directory.  No container stop is required.

**Raw volumes** — all other volumes are tarred verbatim.  If any containers
are labeled `pg-volume-backup.stop-during-backup: "true"`, they are stopped
before the first raw-volume tar and restarted after the last one.

### Archive naming

```
YYYYMMDDTHHMMSS-HOSTNAME-NAME-backup.tar[.EXT][.gpg]
```

The SHA-256 companion always uses `.tar.sha256` (before compression and
encryption) so `rotate-aws-backups` can pair each archive with its checksum
when `GROUP_BY_TIMESTAMP=true`.

### S3 layout

```
s3://<bucket>/<volume-name>/YYYYMMDDTHHMMSS-host-name-backup.tar.gz
s3://<bucket>/<volume-name>/YYYYMMDDTHHMMSS-host-name-backup.tar.sha256
```

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `AWS_S3_BUCKET_NAME` | — | S3 bucket (**required**); may include a key prefix |
| `AWS_CONFIG_FILE` | `/run/secrets/aws-config` | AWS config file |
| `AWS_SHARED_CREDENTIALS_FILE` | `/run/secrets/aws-credentials` | AWS credentials file |
| `AWS_DRYRUN` | `false` | Pass `--dryrun` to AWS CLI |
| `BACKUP_HOSTNAME` | `$(hostname)` | Hostname embedded in archive names |
| `BACKUP_ROOT` | `/backup` | Root under which volume directories are discovered |
| `COMPRESSION` | `none` | `bzip2`, `gzip`, `xz`, `lzop`, `pigz`, or `none` |
| `CRON_EXPRESSION` | `@daily` | Cron schedule for service mode |
| `DB_FORMAT` | `plain` | `pg_dump` format: `plain` or `custom` |
| `DB_HOST` | — | PostgreSQL host (required when `DB_VOLUME` is set) |
| `DB_NAME` | — | Database name (required when `DB_VOLUME` is set) |
| `DB_PASSWORD` | — | Database password (prefer `DB_PASSWORD_FILE`) |
| `DB_PASSWORD_FILE` | `/run/secrets/db-password` | Path to database password file |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | — | Database user (required when `DB_VOLUME` is set) |
| `DB_VOLUME` | — | Volume name to back up with `pg_dump` instead of raw tar |
| `DEBUG` | `false` | Enable `set -x` trace output |
| `GPG_CIPHER_ALGO` | `aes256` | GPG symmetric cipher algorithm |
| `GPG_PASSPHRASE` | — | GPG passphrase (prefer `GPG_PASSPHRASE_FILE`) |
| `GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | Path to GPG passphrase file |
| `TZ` | `UTC` | Timezone for log timestamps and archive names |

All secret variables support a `_FILE` variant that reads the value from a
file at startup (Docker Secrets pattern).

## CLI mode

Run the backup once, immediately, without cron:

```bash
docker run --rm \
  -e AWS_S3_BUCKET_NAME=my-bucket \
  -e COMPRESSION=gzip \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v myvolume:/backup/myvolume:ro \
  1121citrus/pg-volume-backup pg-volume-backup [--dry-run]
```

`--dry-run` logs every action without uploading anything.

```
pg-volume-backup — back up Docker volumes and PostgreSQL databases to S3

Usage: pg-volume-backup [options]

Options:
  -?, --help       Display this help text
  -v, --version    Display command version
  --dry-run        Print actions without executing them
```

## Verify a backup

SHA-256 is computed on the **uncompressed, unencrypted tar**, before any
compression or encryption is applied.  To verify:

```bash
# Decrypt (if encrypted)
gpg --batch --passphrase-file passphrase.txt \
    --pinentry-mode loopback \
    --decrypt backup.tar.gz.gpg > backup.tar.gz

# Decompress
gzip -d backup.tar.gz

# Verify
sha256sum --check backup.tar.sha256
```

## Container stop/start behavior

Containers labeled `pg-volume-backup.stop-during-backup: "true"` are stopped
before the first raw-volume tar runs and restarted after the last one.  The
Docker socket must be mounted for this feature; it can be omitted if all
volumes are backed up with `pg_dump`.

Add the label to services whose volumes need quiescing:

```yaml
services:
  app:
    image: myapp
    labels:
      pg-volume-backup.stop-during-backup: "true"
```

## Retention management

Pair with
[1121citrus/rotate-aws-backups](https://github.com/1121citrus/rotate-aws-backups)
and set `GROUP_BY_TIMESTAMP=true` so that each archive and its SHA-256
companion are rotated together.

## Building

Use the `build` script at the project root.  It wraps `docker buildx` and
handles multi-arch targets, SBOM/provenance attestations, and version tagging.

```bash
# Local dev build — no push, tagged "dev-<git-sha>"
./build --no-scan

# Full build with scan
./build

# Release build — push version 1.2.3 and re-tag latest
./build --push --version 1.2.3

# Full help
./build --help
```

Prerequisites: `docker` with the `buildx` plugin and QEMU binfmt helpers
installed for cross-platform builds:

```bash
docker run --rm --privileged tonistiigi/binfmt --install all
```

## Security

See [SECURITY.md](SECURITY.md) for the full threat model, credential
handling guidance, and S3 hardening recommendations.
Report vulnerabilities through the
[GitHub Security tab](https://github.com/1121citrus/pg-volume-backup/security).
