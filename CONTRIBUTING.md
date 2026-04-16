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
4. Submit a pull request to the `dev` branch

## Release process

Releases are managed by
[release-please](https://github.com/googleapis/release-please).
Merge the release PR to tag and publish.
