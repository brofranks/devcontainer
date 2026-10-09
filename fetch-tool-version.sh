#!/bin/bash
# Variables inside single quotes belong to jq.
# shellcheck disable=SC2016
set -euo pipefail

# Resolve {version, source, artifacts} for one tool. Artifact filters receive
# $version, $uname and $arch; downloads are keyed by name with {url, sha256?} metadata.

tool="$1"
jq_flags=
request=(-fsSL)
artifacts='{}'
archs='{
  "x86_64": {"deb": "amd64", "node": "x64", "jb": ""},
  "aarch64": {"deb": "arm64", "node": "arm64", "jb": "-aarch64"}
}'

case "$tool" in
  node)
    source="https://nodejs.org/dist/index.json"
    filter='[.[] | select(.version | startswith("v24."))][0].version'
    artifacts='{node: {url: "https://nodejs.org/dist/\($version)/node-\($version)-linux-\($arch.node).tar.xz"}}'
    ;;
  npm:*)
    package="${tool#npm:}"
    source="https://registry.npmjs.org/${package//\//%2F}/latest"
    filter='.version'
    ;;
  pypi:*)
    source="https://pypi.org/pypi/${tool#pypi:}/json"
    filter='.info.version'
    ;;
  step | tailcat | gh)
    case "$tool" in
      step) repository=smallstep/cli asset='step_linux_\($version)_\($arch.deb)' ;;
      tailcat) repository=tailscale/tailcat asset='tailcat_\($version)_linux_\($arch.deb)' ;;
      gh) repository=cli/cli asset='gh_\($version)_linux_\($arch.deb)' ;;
    esac
    source="https://api.github.com/repos/$repository/releases/latest"
    filter='.tag_name | ltrimstr("v")'
    artifacts="{$tool: (.assets | map(select(.name == \"$asset.tar.gz\"))[0] | {url: .browser_download_url, sha256: .digest})}"
    ;;
  vscode)
    source="https://update.code.visualstudio.com/api/update/server-linux-x64/stable/latest"
    filter='.version | select(test("^[a-f0-9]{40}$"))'
    artifacts='{
      "vscode-cli": {url: "https://update.code.visualstudio.com/commit:\($version)/cli-alpine-\($arch.node)/stable"},
      "vscode-server": {url: "https://update.code.visualstudio.com/commit:\($version)/server-linux-\($arch.node)/stable"}
    }'
    ;;
  cursor)
    source="https://api2.cursor.sh/updates/api/update/linux-arm64/cursor/0.0.0/stable"
    filter='.url | capture("/production/(?<commit>[a-f0-9]{40})/").commit'
    artifacts='{"cursor-server": {url: "https://downloads.cursor.com/production/\($version)/linux/\($arch.node)/cursor-reh-linux-\($arch.node).tar.gz"}}'
    ;;
  cursor-cli)
    # The installer script advertises the current release.
    source="https://cursor.com/install"
    jq_flags=Rs
    filter='capture("https://downloads.cursor.com/lab/(?<version>[^/]+)/").version'
    artifacts='{"cursor-cli": {url: "https://downloads.cursor.com/lab/\($version)/linux/\($arch.node)/agent-cli-package.tar.gz"}}'
    ;;
  jetbrains-idea)
    source="https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release"
    filter='.IIU[0] | {version, build}'
    artifacts='{"jetbrains-idea": {url: "https://download.jetbrains.com/idea/ideaIU-\($version)\($arch.jb).tar.gz"}}'
    ;;
  jetbrains-gateway)
    source="https://data.services.jetbrains.com/products/releases?code=GW&latest=true&type=release"
    filter='.GW[0].version'
    artifacts='{"jetbrains-gateway": {url: "https://download.jetbrains.com/idea/gateway/JetBrainsGateway-\($version)\($arch.jb).tar.gz"}}'
    ;;
  ideavim)
    # Select the newest plugin compatible with the already-resolved IDEA build.
    source="https://plugins.jetbrains.com/pluginManager?action=download&id=IdeaVIM&build=IU-${2:?IDEA build is required}"
    request=(-fsSI)
    jq_flags=Rs
    filter='capture("(?im)^location: \\S*/IdeaVIM-(?<version>[^/?]+)\\.zip").version'
    artifacts='{ideavim: {url: capture("(?im)^location: (?<url>https://plugins\\.jetbrains\\.com/\\S+)").url}}'
    ;;
  claude-code)
    source="https://downloads.claude.ai/claude-code-releases/latest"
    jq_flags=R
    filter='.'
    ;;
  antigravity)
    source="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json"
    filter='.url | capture("/antigravity-cli/(?<release>[^/]+)/").release'
    artifacts='{antigravity: {url: "https://storage.googleapis.com/antigravity-public/antigravity-cli/\($version)/linux-\($arch.node | sub("arm64"; "arm"))/cli_linux_\($arch.node).tar.gz"}}'
    ;;
  awscli)
    source="https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst"
    jq_flags=Rn
    filter='[inputs | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))][0]'
    artifacts='{awscli: {url: "https://awscli.amazonaws.com/awscli-exe-linux-\($uname)-\($version).zip"}}'
    ;;
  *)
    echo "Unsupported tool: $tool" >&2
    exit 1
    ;;
esac

curl "${request[@]}" "$source" | jq "-ce$jq_flags" --arg source "$source" --argjson archs "$archs" '
  . as $response
  | ('"$filter"' | if type == "string" then {version: .} else . end) as $meta
  | $meta.version as $version
  | $meta + {source: $source, artifacts: ($archs | with_entries(
      .key as $uname | .value as $arch | .value = ($response | '"$artifacts"')))}
  | select(.version | test("^[a-zA-Z0-9._+-]+$"))
  | select(all(.artifacts[][]; .url | test("^https://")))
  | select(all(.artifacts[][] | select(has("sha256")) | .sha256; test("^sha256:[a-f0-9]{64}$")))'
