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

As of 2026-07-10, the runtime image has had a focused vulnerability-reduction
pass against every package family reported by Trivy, Grype, and Docker Scout.

### Remediation completed

- Rebuilt from the current `aws-backup-base:latest` and removed child-specific
  Python overlay customizations so scanner output is easier to attribute
- Built `supercronic` from source in the child image so the final runtime no
  longer inherits the base image's Go stdlib scan data
- Removed the unused Perl runtime stack from the final image
- Removed the unused `python3-pygments` package from the final image
- Removed `python3-setuptools` and `python3-setuptools-wheel` from the final
  image after validating that neither the backup workflow nor the AWS CLI
  runtime required them
- Relied on the shared `awscli-2` package from `aws-backup-base` for the AWS
  CLI runtime instead of carrying a separate Python overlay in this image

### Current scanner posture

Current local validation after those changes shows:

- Trivy: child-specific Python overlay findings were removed; remaining gating
  results should now be limited to the shared base digest and current ignore
  policy
- Grype: child-specific Python overlay findings were removed; remaining
  advisory results should now be limited to shared base content and feed state
- Docker Scout: residual findings should now be limited to the shared base
  image rather than child-specific Python or Go stdlib packages

### Remaining findings and why they remain

#### Inherited scanner findings

Any remaining scanner findings in this image are inherited from the shared base
image, most notably the AWS CLI package shipped there. The child image no
longer adds a separate `urllib3`/`idna` overlay and now ships its own
`supercronic` binary built from source.

### Revalidation guidance

When upstreams move, re-run these checks before changing the shared base image
or introducing new runtime dependencies:

- `./build --cache 'reset=all'`
- `docker scout quickview 1121citrus/pg-volume-backup:latest`
- `docker scout cves --only-vuln-packages 1121citrus/pg-volume-backup:latest`

If `aws-backup-base` publishes a new `supercronic` toolchain or a different AWS
CLI packaging approach becomes available, re-test whether the child image can
remain free of inherited Python package findings.
