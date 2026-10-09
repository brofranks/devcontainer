#!/bin/bash
set -euo pipefail

# Delete superseded GHCR versions, keeping stable and its per-arch manifests.
# Deletes by default; `--dry-run` (`-n`) only previews.
# Requires a Docker login and a GH_TOKEN with packages: write; failing to read
# stable aborts before any deletion.
# Assumes provenance and SBOM are disabled; attestations would also need keeping.

versions="/users/$GHCR_OWNER/packages/container/$GHCR_PACKAGE/versions"

verb="Deleting"
delete=(gh api -X DELETE)
case "${1:-}" in
  -n | --dry-run)
    verb="Would delete"
    delete=(:)
    ;;
  "") ;;
  *)
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
    ;;
esac

keep="$(docker buildx imagetools inspect "ghcr.io/$GHCR_OWNER/$GHCR_PACKAGE:stable" --raw | jq -c '[.manifests[].digest]')"
echo "Keeping stable and $keep"

gh api --paginate "$versions?per_page=100" \
  | jq -r --argjson keep "$keep" '.[]
      | select((.metadata.container.tags | index("stable") | not) and (.name | IN($keep[]) | not))
      | [.id, .name, (.metadata.container.tags | join(","))] | @tsv' \
  | while IFS=$'\t' read -r id name tags; do
    echo "$verb version $id $name [$tags]"
    "${delete[@]}" "$versions/$id"
  done
