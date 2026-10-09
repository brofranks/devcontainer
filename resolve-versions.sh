#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# The ISO-week build argument refreshes unpinned inputs by invalidating RUN layers.
snapshot="$(jq -n --arg epoch "$(date -u +%G-W%V)" \
  '{cache_epoch: $epoch, tools: {}, npm: {}, pypi: {}}')"

for spec in \
  tools:node tools:vscode tools:cursor tools:cursor-cli \
  tools:jetbrains-idea tools:jetbrains-gateway tools:ideavim \
  tools:claude-code tools:antigravity tools:gh tools:awscli tools:step tools:tailcat \
  npm:@openai/codex npm:@google/gemini-cli npm:@github/copilot npm:opencode-ai \
  pypi:openai pypi:typing-extensions; do
  args=("${spec#tools:}")
  if [ "$spec" = tools:ideavim ]; then
    args+=("$(jq -er '.tools["jetbrains-idea"].build' <<< "$snapshot")")
  fi
  metadata="$(./fetch-tool-version.sh "${args[@]}")"
  snapshot="$(jq --arg group "${spec%%:*}" --arg id "${spec#*:}" --argjson metadata "$metadata" \
    '.[$group][$id] = $metadata' <<< "$snapshot")"
done

# All pinned build inputs come from this snapshot.
jq -S . <<< "$snapshot" | tee versions.json
jq -r '"CACHE_EPOCH=\(.cache_epoch)", (.tools | to_entries[] | "\(.key | ascii_upcase | gsub("-"; "_"))_VERSION=\(.value.version)")' versions.json > .env
jq '{private: true, dependencies: (.npm | map_values(.version))}' versions.json > package.json
jq -r '.pypi | to_entries[] | "\(.key)==\(.value.version)"' versions.json > requirements.txt
