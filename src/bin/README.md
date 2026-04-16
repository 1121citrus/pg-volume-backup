# src/bin — script reference

Scripts installed to `/usr/local/bin` inside the container image.

---

## Script inventory

| Script | Role | Entry point |
| --- | --- | --- |
| `pg-volume-backup` | **Primary CLI** — discovers volumes, runs backup pipelines, uploads to S3 | user / cron |
| `backup` | Service script — sources `.env` and invokes `pg-volume-backup` | cron (via `startup`) |
| `startup` | Container entrypoint — writes `.env`, installs crontab, hands off to `crond` | `CMD` in Dockerfile |
| `healthcheck` | Docker `HEALTHCHECK` — verifies `crond` is running and the crontab is configured | Docker daemon |

---

## Data flow

### CLI mode

```text
caller
  └─ pg-volume-backup [--dry-run]
        ├─ discover volumes under BACKUP_ROOT/
        ├─ stop labeled containers (if raw-tar volumes present)
        │
        ├─ for each volume:
        │     ├─ [pg_dump path]  PGPASSWORD pg_dump → dump file → tar
        │     └─ [raw-tar path]  tar BACKUP_ROOT/<name>/ → tar file
        │
        ├─ restart stopped containers
        │
        └─ for each tar file:
              ├─ sha256sum → .tar.sha256
              ├─ compress  → .tar[.bz2|.gz|.xz|.lzo]  (optional)
              ├─ gpg --symmetric → .gpg                 (optional)
              └─ aws s3 mv → s3://bucket/<name>/
```

### Service mode

```text
Docker CMD
  └─ startup
        └─ crond (daemon)
              └─ backup  (on schedule)
                    └─ pg-volume-backup
```

---

## `pg-volume-backup`

The user-facing CLI.  Resolves `_FILE` secrets, validates required variables,
discovers volumes under `BACKUP_ROOT`, and runs the full backup pipeline.

### Volume discovery

`pg-volume-backup` lists every subdirectory of `BACKUP_ROOT` (default
`/backup`) and treats each one as a backup target.  The directory name becomes
the volume name used in the archive filename and the S3 key prefix.

### Backup pipelines

**PostgreSQL path** — when `DB_VOLUME` matches the current volume name,
`pg_dump` is called over the network.  No container stop is needed; the
database handles consistency internally.  The dump is written to a temp file,
tarred, and the dump file removed.

**Raw-tar path** — all other volumes are tarred verbatim from `BACKUP_ROOT/<name>`.
If any containers are labeled `pg-volume-backup.stop-during-backup: "true"`,
they are stopped before the first raw-tar volume and restarted after the last.

### SHA256 ordering

The checksum is computed against the **uncompressed, unencrypted tar** before
any compression or encryption is applied.  The companion file always uses the
`.tar.sha256` extension regardless of the compression format.  Verification
therefore requires decrypting and decompressing before running `sha256sum`.

### `_FILE` secret resolution

`GPG_PASSPHRASE` and `DB_PASSWORD` each support a `_FILE` variant.  The CLI
reads the file once at startup and stores the value in the plain variable.
Plain variable values take precedence over file-based ones.

---

## `backup`

Thin service script invoked by cron.  Sources `~/.env` (written by `startup`)
and delegates to `pg-volume-backup`.

---

## `startup`

Container entrypoint for service mode.  Writes all runtime configuration to
`~/.env`, redacting `DB_PASSWORD` and `GPG_PASSPHRASE` in log output.
Installs a crontab entry, then runs `crond -l 2 -f` in the foreground.

The `.env` write-and-source pattern is needed because `crond` runs jobs with a
minimal environment; writing the configuration to a file that each job sources
is simpler than threading variables through `crond`'s own environment
mechanisms.

---

## `healthcheck`

Checks two conditions:

1. `crond` is running (`pidof` with `pgrep` fallback for portability)
2. The crontab contains a `/backup` entry

Whether the cron job has run successfully is not checked: Alpine's `crond`
writes no structured execution log, so detecting the last successful run
requires an external sentinel file.
