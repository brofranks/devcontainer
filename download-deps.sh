#!/bin/bash
set -euo pipefail

# Cache host-architecture artifacts from versions.json for Dockerfile bind mounts.

cd "$(dirname "${BASH_SOURCE[0]}")"

uname="$(uname -m)"
echo "Downloading dependencies to .cache/ for $uname..."

# Reuse matching pins; replace older versions in each artifact directory.
jq -r --arg uname "$uname" '.tools[] | .version as $version | .artifacts[$uname] | to_entries[]
    | [.key, $version, .value.url, .value.sha256] | @tsv' versions.json \
  | while IFS=$'\t' read -r name version url sha256; do
    dir=".cache/$name" file="$name-$version-$uname"

    if [ -f "$dir/$file" ]; then
      echo "  Cached: $file"
    else
      rm -rf "$dir"
      mkdir -p "$dir"

      echo "  Downloading: $file"
      curl -fsSL "$url" -o "$dir/$file.part"
      mv "$dir/$file.part" "$dir/$file"
    fi

    # Verify published checksums before the Docker build consumes them, including
    # for restored archives.
    if [ -n "$sha256" ]; then
      printf '%s  %s\n' "${sha256#sha256:}" "$dir/$file" | sha256sum -c -
    fi
  done
