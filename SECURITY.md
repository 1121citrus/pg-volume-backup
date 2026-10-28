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

As of 2026-10-28, the runtime image was rebuilt against
`aws-backup-base:1.2.2` and re-validated against Trivy, Grype, and Docker
Scout with freshly downloaded vulnerability databases.

### Remediation completed (2026-09-03)

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

### Remediation completed (2026-10-28)

- Rebuilt against `aws-backup-base:1.2.2` (AL2023 digest refreshed to
  2026-10-28), whose `dnf upgrade` now pulls PostgreSQL
  `15.19-1.amzn2023.0.1` — resolving every previously-suppressed
  `postgresql15` / `postgresql15-private-libs` CVE (23 entries removed from
  `.trivyignore`)
- Fixed the same `GOTOOLCHAIN` pinning defect `aws-backup-base` had already
  fixed in its own builder: this image's `supercronic-builder` stage
  hardcoded `GOTOOLCHAIN=go1.27.1`, which silently overrode the builder
  image tag and froze the compiled `supercronic` binary's embedded Go
  stdlib regardless of how recent `golang:*-alpine` was. Bumped both the
  `supercronic-builder` and `docker-cli-builder` stages to
  `golang:1.27.3-alpine`, bumped `SUPERCRONIC_VERSION` to `v0.2.49`, and
  changed `GOTOOLCHAIN=go1.27.1` to `GOTOOLCHAIN=local`. This resolved 2
  CRITICAL and 11 HIGH/MEDIUM Go stdlib findings that Grype and Docker
  Scout attributed to both the `docker` and `supercronic` gobinaries (none
  of which Trivy had flagged — its cached DB predated the advisories; see
  "Scanner DB freshness" below)
- Added a Grype suppression for `urllib3` `GHSA-q2q7-5pp4-w6pg`
  (`CVE-2021-33503`), mirroring `aws-backup-base`'s own `.grype.yaml`: AL2023
  confirmed "Not Affected"
- Removed the now-stale `.grype.yaml` entries for `glibc` / `glibc-common` /
  `glibc-minimal-langpack` (`CVE-2026-4046`) and `python3` / `python3-libs`
  (`CVE-2026-3644`, `CVE-2026-4786`, `CVE-2026-6100`) — a fresh Grype scan no
  longer reports any of them against the current package versions
- Removed the now-stale `.trivyignore` entries resolved by the
  `aws-backup-base:1.2.2` AL2023 digest refresh: `gnutls`, the
  misattributed-`libcap` Go stdlib batch, `libsolv`,
  `openssl-fips-provider-latest` / `openssl-libs`, `glib2`, and `libacl`
- Removed the `supercronic` Go stdlib suppression (`CVE-2026-42504`); the
  toolchain fix above resolves it

### Scanner DB freshness

Trivy's cached CVE database can lag what Grype or Docker Scout report, even
within the same build run, because `./build` only re-downloads it when the
cache volume is completely empty. A stale cache can make Trivy report a
clean image that a fresh scan would not — this happened during the
2026-10-28 remediation pass. Before relying on a Trivy "0 findings" result
for a security decision, re-run with `./build --cache 'reset=all'` (or at
least `--cache 'reset=trivy'`) to confirm the DB itself is current.

### Current scanner posture (2026-10-28, fresh DBs, `aws-backup-base:1.2.2`)

- Trivy (HIGH/CRITICAL, `--ignore-unfixed`): 0 findings, across the AL2023
  layer and both the `docker` and `supercronic` gobinaries
- Grype (full severity): 9 findings, all RPM packages inherited from the
  base image with no AL2023 build available yet (same CVEs tracked in
  `.trivyignore`; see table below)
- Docker Scout: 31 findings across 13 packages (0 CRITICAL / 25 HIGH / 6
  MEDIUM), all either (a) the same inherited AL2023 RPM CVEs tracked in
  `.trivyignore`, or (b) `urllib3`/`idna` version-string feed mismatches
  (see below). Docker Scout has no suppression file wired into `./build`,
  so these always surface in its report regardless of triage status.

### Remaining findings and why they remain

#### Inherited AL2023 RPM findings — fix not yet in the repo mirror

Verified via `dnf list --showduplicates <pkg>` against the live AL2023 repo
mirror on 2026-10-28 (the same day as `aws-backup-base`'s own digest
refresh): no build matching the "Fixed Version" the scanners report exists
yet. Tracked in `.trivyignore`; mirrors the identical set documented in
`aws-backup-base`'s own `SECURITY.md`.

| CVE | Component(s) | Fixed version (not yet in repo) |
| --- | --- | --- |
| `CVE-2026-113470` | `ca-certificates` | `2025.2.76-1.0.amzn2023.0.4` |
| `CVE-2026-92392` | `curl` / `curl-minimal` / `libcurl-minimal` | `8.21.0-5.amzn2023.0.3` |
| `CVE-2026-107161` | `cyrus-sasl` / `cyrus-sasl-lib` | `2.1.27-18.amzn2023.0.4` |
| `CVE-2026-78659`, `CVE-2026-78667`, `CVE-2026-94440` | `libcap` | `2.73-1.amzn2023.0.8` |
| `CVE-2026-103111`, `CVE-2026-86145`, `CVE-2026-89156`, `CVE-2026-89160` | `pcre2` / `pcre2-syntax` | `10.40-1.amzn2023.0.5` |
| `CVE-2026-19553` | `python3` / `python3-libs` | `3.9.25-1.amzn2023.0.11` |

#### urllib3 / idna — version-string feed mismatches (mostly false positives)

AL2023 backports security fixes into `python3-urllib3` and `python3-idna`
without bumping the upstream PyPI version string, so Grype and Docker Scout
read the stale `1.25.10` / `2.10` version from package metadata and flag
CVEs the installed RPM already patches. Verified via
`rpm -q --changelog python3-urllib3 python3-idna` against the actual
installed packages (`python3-urllib3-1.25.10-5.amzn2023.0.9`,
`python3-idna-2.10-3.amzn2023.0.4` — both the latest AL2023 build available
per `dnf list --showduplicates`):

| CVE | Package | Status |
| --- | --- | --- |
| `CVE-2026-97689` | `urllib3` | Fixed per `.amzn2023.0.9` changelog |
| `CVE-2023-45803` | `urllib3` | Fixed per `.amzn2023.0.8` changelog |
| `CVE-2026-44431` | `urllib3` | Fixed per `.amzn2023.0.7` changelog |
| `CVE-2025-66418`, `CVE-2025-66471`, `CVE-2026-21441` | `urllib3` | Fixed per `.amzn2023.0.6` changelog |
| `CVE-2025-50181` | `urllib3` | Fixed per `.amzn2023.0.5` changelog |
| `CVE-2023-43804` | `urllib3` | Fixed in `.amzn2023.0.6` (ALAS2023-2023-454); predates the RPM's recorded changelog window |
| `CVE-2021-33503` | `urllib3` | AL2023 confirmed "Not Affected"; suppressed in `.grype.yaml` (`GHSA-q2q7-5pp4-w6pg`) |
| `CVE-2026-45409` | `idna` | Fixed per `.amzn2023.0.4` changelog |
| `CVE-2024-3651` | `idna` | Fixed per `.amzn2023.0.3` changelog |

**`CVE-2024-37891` (`urllib3`, MEDIUM) is the one open exception: status
unconfirmed.** The installed `python3-urllib3-1.25.10-5.amzn2023.0.9` is
the latest AL2023 build available (confirmed via `dnf list
--showduplicates`), but its RPM changelog does not explicitly list a fix
for this CVE, unlike every other entry above. It may predate the
changelog's recorded window (as `CVE-2023-43804` does) or it may be a
genuine gap. Not suppressed in `.grype.yaml` pending confirmation from
Amazon Linux Security — re-check `alas.aws.amazon.com` or the RPM
changelog when `python3-urllib3` next updates.

### Revalidation guidance

When upstreams move, re-run these checks before changing the shared base image
or introducing new runtime dependencies:

- `./build --cache 'reset=all' --advise all`
- `docker scout quickview 1121citrus/pg-volume-backup:latest`
- `docker scout cves --only-vuln-packages 1121citrus/pg-volume-backup:latest`

If `aws-backup-base` publishes a newer AL2023 digest, or `python3-urllib3`/
`python3-idna` receives a newer AL2023 build, re-run
`rpm -q --changelog <pkg>` against the new package to confirm which
suppressions (and the `CVE-2024-37891` open item above) are still needed.
