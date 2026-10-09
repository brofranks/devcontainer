# Devcontainer

Debian trixie | amd64 / arm64

## Run

```bash
docker pull ghcr.io/brofranks/devcontainer:stable
docker run --rm -it --user coder \
  -v "$PWD:/work" -w /work \
  ghcr.io/brofranks/devcontainer:stable bash
```

## Versions

```bash
docker run --rm --entrypoint cat \
  ghcr.io/brofranks/devcontainer:stable \
  /usr/local/share/devcontainer/versions.json
```

## Builds

- Daily: 01:17 UTC
- Fresh Docker layers: first build of each ISO week
- Manual: **Actions > Build devcontainer image > Run workflow**
- Published tag: `stable`; only the current image is retained
- GitHub Actions dependencies: weekly Dependabot PRs
