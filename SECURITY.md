# Security considerations

This document describes the security model, known limitations, and recommended
hardening steps for `pg-volume-backup`.

## Threat model

The service runs as a scheduled container that:

1. Optionally stops labeled Docker Compose services to quiesce volumes.
2. Runs `pg_dump` against a PostgreSQL instance over the internal network,
   or tars raw Docker volumes.
3. Optionally compresses and encrypts archives with GPG (AES-256).
4. Uploads archives and SHA-256 checksums to an S3 bucket.

Trusted components: the container host, the Docker daemon, the internal
network path to PostgreSQL, the S3 bucket (access-controlled by IAM), and
the Docker socket (used only to stop/start labeled containers).

## Credential handling

All credentials — AWS access keys, GPG passphrase, database password — are
supplied via Docker secrets mounted at `/run/secrets/`.  The `_FILE` variant
of each variable reads the secret file at startup rather than accepting the
value as a plain environment variable.

**Never pass credentials as plain environment variables in production.**
Plain env vars are visible in `docker inspect` output and process listings.

The `startup` script redacts `DB_PASSWORD` and `GPG_PASSPHRASE` from log
output before writing them to the env file.

## Docker socket exposure

Stopping and restarting labeled containers requires the Docker socket
(`/var/run/docker.sock`).  The socket grants root-equivalent access to the
Docker daemon.  Mitigations:

- Mount the socket read-write only when container stop/start is required.
- If all volumes use `pg_dump` (no raw-tar volumes), the socket mount can
  be omitted entirely.
- Restrict which containers the backup service can reach via Docker network
  isolation.

## S3 hardening recommendations

- Use a dedicated IAM user or role with the minimum required permissions:
  `s3:PutObject` and `s3:GetObject` for the backup bucket prefix.
- Use a separate IAM credential for `rotate-aws-backups` with only
  `s3:DeleteObject` and `s3:ListBucket`.
- Enable S3 bucket versioning and MFA Delete for additional protection
  against accidental or malicious deletion.
- Consider enabling S3 server-side encryption (SSE-S3 or SSE-KMS) as a
  second layer alongside GPG client-side encryption.

## Reporting vulnerabilities

Report vulnerabilities through the
[GitHub Security tab](https://github.com/1121citrus/pg-volume-backup/security).

## Scanner status and CVE triage

As of 2026-06-08, local staging runs built from a freshly rebuilt local base
image run clean for Trivy HIGH/CRITICAL findings.

GitHub CI currently builds against the published
`1121citrus/aws-backup-base:latest`, which may lag behind local rebuilt base
content. For this reason, `.trivyignore` contains temporary suppressions for
known HIGH findings tied to that published-base lag.

### Scout HIGH findings handled

- Rebuilt `pg-volume-backup:latest` from the locally rebuilt
  `aws-backup-base:latest` so `supercronic` is compiled with Go 1.26.4,
  removing the Go stdlib HIGH finding (`CVE-2026-42504`)
- Updated AL2023 package set in the final image so previously ignored HIGH
  RPM findings are now fixed in-image:
  - `glibc-2.34-231.amzn2023.0.4`
  - `python3-libs-3.9.25-1.amzn2023.0.5`
  - `gnutls-3.8.3-8.amzn2023.0.3`
  - `libcap-2.73-1.amzn2023.0.7`

### Temporary CI suppressions

The following CVEs remain in `.trivyignore` only to keep CI green while the
published base image catches up to the rebuilt secure base:

- `CVE-2026-33846`
- `CVE-2026-3833`
- `CVE-2026-42009`
- `CVE-2026-42010`
- `CVE-2026-42014`
- `CVE-2026-42015`
- `CVE-2026-5260`
- `CVE-2026-27142`
- `CVE-2026-33811`
- `CVE-2026-33814`
- `CVE-2026-39820`
- `CVE-2026-39823`
- `CVE-2026-42499`
- `CVE-2026-42504`

Remove these suppressions once CI uses a refreshed `aws-backup-base:latest`
that contains the fixed package/toolchain levels.

### Scout HIGH findings not currently remediable in AL2023

Remaining Scout HIGHs are tied to AL2023-published package versions for
`python3-urllib3`, `python3-setuptools`, and perl subpackages.

Current verification:

- `dnf list --showduplicates python3-urllib3 python3-setuptools perl-interpreter`
  shows the installed versions are already the newest available in the
  configured AL2023 repositories
- Removing `python3-urllib3` also removes `awscli-2`, which is required by the
  backup workflow

These findings are tracked as upstream repository constraints and should be
reassessed when newer AL2023 RPMs are published.
