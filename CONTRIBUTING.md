# Contributing

## Prerequisites

- Docker with buildx support
- Bash 4.0+

## Development workflow

### Building

The `build` script runs all stages: lint → build → test → scan → push.

```bash
./build              # Local build and test
./build --push       # Push to Docker Hub
./build --help       # See all options
```

### Testing

Run the test suite against a locally built image:

```bash
./build --no-scan
```

Or manually:

```bash
docker buildx build -t 1121citrus/pg-volume-backup:test .
IMAGE=1121citrus/pg-volume-backup:test test/run-all
```

### Code style

All shell scripts must pass:

```bash
shellcheck src/common-functions src/bin/* test/run-all test/staging test/bin/*
hadolint Dockerfile
```

The `./build` stage runs these automatically.

### Submitting changes

1. Create a branch from `dev`
2. Make your changes
3. Run `./build --no-scan` to lint, build, and test
4. Submit a pull request to the `dev` branch to exercise CI
5. After `dev` is validated, submit a pull request from `dev` to `staging`

## Protected branches and tags

`main` cannot be force-pushed or deleted. The required GitHub Actions checks
are listed in **Settings > Rules > Rulesets > Require main checks**. Missing
or failed checks block updates; GitHub also accepts skipped and neutral
results. The repository owner is the only actor allowed to create, update,
or delete `v*` tags.

Inspect and fix failed Actions runs before retrying. If a check is missing,
verify that its workflow runs on the source branch. After renaming a check,
verify the new name on a branch and update the ruleset before promoting that
change to `main`.

## Release process

After the release commit passes the required checks and the release is
approved, the repository owner creates and pushes its `v*` tag. The tag
triggers the image release workflow.
