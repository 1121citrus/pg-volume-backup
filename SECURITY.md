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

- Rebuilt from the current `aws-backup-base:latest`, which already carries a
  clean Amazon Linux 2023 base image from Scout's perspective
- Removed the unused Perl runtime stack from the final image
- Removed the unused `python3-pygments` package from the final image
- Removed `python3-setuptools` and `python3-setuptools-wheel` from the final
  image after validating that neither the backup workflow nor the AWS CLI
  runtime required them
- Replaced the AL2023-packaged `python3-urllib3` and `python3-idna` RPMs with
  current PyPI builds installed directly into the image runtime:
  - `urllib3==2.6.3`
  - `idna==3.15`

### Current scanner posture

Current local validation after those changes shows:

- Trivy: only two remaining HIGH findings, both against `urllib3 2.6.3`
- Grype: one HIGH (`urllib3`), two MEDIUM (`urllib3`, `idna`), one MEDIUM and
  one HIGH in the Go stdlib bundled into `supercronic`, and one LOW in
  `golang.org/x/sys`
- Docker Scout quickview: `0C 2H 0M 1L 2?`

### Remaining findings and why they remain

#### `urllib3`

The build now installs the newest version currently available on the reachable
package index: `urllib3 2.6.3`.

Remaining Trivy HIGH findings:

- `CVE-2026-44431`
- `CVE-2026-44432`

Those findings require `urllib3 >= 2.7.0`, which is not currently available to
the build environment. Docker Scout also reports the same package family as the
dominant remaining source of HIGH findings.

#### Go runtime findings in `supercronic`

Remaining non-Python findings are inherited from the `supercronic` binary
shipped by `aws-backup-base`:

- `CVE-2026-42505`
- `CVE-2026-39822`
- `CVE-2026-39824`

These are base-image/toolchain findings. They must be fixed in
`aws-backup-base` and then picked up by rebuilding this image.

### Temporary Trivy suppressions

`.trivyignore` now serves two purposes:

- carry forward the existing AL2023 / upstream-package suppressions inherited
  from the broader backup-image family
- suppress the two `urllib3 2.6.3` HIGH findings until `urllib3 2.7.0` (or a
  later fixed release) is available to the image build

The `urllib3` suppressions are:

- `CVE-2026-44431`
- `CVE-2026-44432`

Remove them once a fixed `urllib3` release newer than `2.6.3` is available and
validated with the AWS CLI runtime.

### Revalidation guidance

When upstreams move, re-run these checks before removing suppressions:

- `./build --cache 'reset=all'`
- `docker scout quickview 1121citrus/pg-volume-backup:latest`
- `docker scout cves --only-vuln-packages 1121citrus/pg-volume-backup:latest`

If `aws-backup-base` publishes a new `supercronic` toolchain or Amazon Linux
2023 publishes newer compatible Python packages, re-test whether the direct
PyPI overlay remains necessary or whether the image can return to fully
repository-managed dependencies.
