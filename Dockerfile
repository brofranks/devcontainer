FROM debian:trixie-slim

# Fail a RUN on any failed command, including inside pipes and loops.
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# The ISO week from resolve-versions.sh keys every RUN below, so the first
# build of each week rebuilds all layers and refreshes unpinned inputs.
ARG CACHE_EPOCH

ENV USERNAME=coder
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Keep downloaded packages for the apt cache mounts below; see https://github.com/debuerreotype/debuerreotype/blob/45491f2/scripts/debuerreotype-minimizing-config#L89
RUN rm -f /etc/apt/apt.conf.d/docker-clean

# System packages
RUN --mount=type=cache,id=apt-cache,sharing=locked,target=/var/cache/apt \
  --mount=type=cache,id=apt-lists,sharing=locked,target=/var/lib/apt/lists \
  apt-get update \
  && apt-get install -y \
    adduser \
    age \
    bubblewrap \
    ca-certificates \
    curl \
    dnsutils \
    fd-find \
    file \
    g++ \
    gcc \
    git \
    gnupg \
    groff-base \
    heaptrack \
    inetutils-ping \
    inotify-tools \
    iproute2 \
    jq \
    less \
    linux-perf \
    locales \
    ncat \
    netcat-openbsd \
    nvi \
    openssh-server \
    poppler-utils \
    python-is-python3 \
    python3 \
    python3-pip \
    python3-requests \
    python3-setuptools \
    python3-venv \
    python3-yaml \
    ripgrep \
    rsync \
    sudo \
    supervisor \
    time \
    unzip \
    wget \
    whois \
    xz-utils \
    zip \
  && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Step CLI (for CA operations)
ARG STEP_VERSION
RUN --mount=type=bind,source=.cache/step,target=/tmp/step-cache \
  tar -xf "/tmp/step-cache/step-${STEP_VERSION}-$(uname -m)" \
    -C /usr/local/bin --strip-components=2 "step_${STEP_VERSION}/bin/step"

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen

# Python packages
RUN --mount=type=cache,id=pip-cache,sharing=locked,target=/root/.cache/pip \
  --mount=type=bind,source=requirements.txt,target=/tmp/requirements.txt \
  python3 -m pip install --break-system-packages --ignore-installed --root-user-action=ignore \
    -r /tmp/requirements.txt

# User setup and sudo configuration
RUN addgroup --gid 1000 "$USERNAME" \
  && adduser --uid 1000 --gid 1000 --disabled-password "$USERNAME" \
  && echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME" \
  && chmod 0440 "/etc/sudoers.d/$USERNAME"

# On-demand SSH server configuration (`sshd -i` over `docker exec`)
RUN mkdir -p /run/sshd \
  && printf 'PasswordAuthentication no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/disable-password-auth.conf

COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER $USERNAME

# SSH directory (the client configuration disables known_hosts checking)
RUN mkdir -p ~/.config \
  && install -d -m 700 ~/.ssh \
  && install -m 600 /dev/null ~/.ssh/authorized_keys \
  && printf 'Host *\n    StrictHostKeyChecking no\n    UserKnownHostsFile=/dev/null\n' | install -m 600 /dev/stdin ~/.ssh/config

ENV PATH="/home/$USERNAME/.local/bin:$PATH"

# JetBrains IDEA
ARG JETBRAINS_IDEA_VERSION
RUN --mount=type=bind,source=.cache/jetbrains-idea,target=/tmp/jetbrains-idea-cache \
  dist_dir="$HOME/.cache/JetBrains/RemoteDev/dist" \
  && mkdir -p "$dist_dir" \
  && tar -xf "/tmp/jetbrains-idea-cache/jetbrains-idea-${JETBRAINS_IDEA_VERSION}-$(uname -m)" -C "$dist_dir" \
  && touch "$(echo "$dist_dir"/idea-IU-*)/.expandSucceeded"

# JetBrains Gateway remote-dev worker
ARG JETBRAINS_GATEWAY_VERSION
RUN --mount=type=bind,source=.cache/jetbrains-gateway,target=/tmp/jetbrains-gateway-cache \
  worker="remote-dev-worker-linux-$(dpkg --print-architecture)" \
  && worker_dir="$HOME/.cache/JetBrains/RemoteDev/remote-dev-worker" \
  && mkdir -p "$worker_dir" \
  && tar -xf "/tmp/jetbrains-gateway-cache/jetbrains-gateway-${JETBRAINS_GATEWAY_VERSION}-$(uname -m)" \
    -C "$worker_dir" --strip-components=3 --wildcards "*/lib/remote-dev-workers/$worker" \
  && mv "$worker_dir/$worker" "$worker_dir/remote-dev-worker_$(sha256sum "$worker_dir/$worker" | cut -d' ' -f1)"

# Cursor Server
ARG CURSOR_VERSION
RUN --mount=type=bind,source=.cache/cursor-server,target=/tmp/cursor-server-cache \
  mkdir -p ~/.cursor-server/bin /tmp/cursor-extract \
  && tar -xf "/tmp/cursor-server-cache/cursor-server-${CURSOR_VERSION}-$(uname -m)" -C /tmp/cursor-extract \
  && mv /tmp/cursor-extract/* ~/.cursor-server/bin/"$(jq -er '.commit' /tmp/cursor-extract/*/product.json)" \
  && rmdir /tmp/cursor-extract

# Visual Studio Code CLI and server
ARG VSCODE_VERSION
RUN --mount=type=bind,source=.cache/vscode-cli,target=/tmp/vscode-cli-cache \
  --mount=type=bind,source=.cache/vscode-server,target=/tmp/vscode-server-cache \
  server_dir="$HOME/.vscode-server/cli/servers/Stable-$VSCODE_VERSION/server" \
  && mkdir -p "$server_dir" \
  && tar -xf "/tmp/vscode-cli-cache/vscode-cli-${VSCODE_VERSION}-$(uname -m)" -C ~/.vscode-server \
  && mv ~/.vscode-server/code ~/.vscode-server/"code-$VSCODE_VERSION" \
  && tar -xf "/tmp/vscode-server-cache/vscode-server-${VSCODE_VERSION}-$(uname -m)" -C "$server_dir" --strip-components=1

# IdeaVim and bash configuration
COPY --chown=$USERNAME:$USERNAME .ideavimrc .bashrc /home/$USERNAME/

# Keep frequently updated tools after the large editor layers for cache reuse.

# IdeaVim plugin
ARG IDEAVIM_VERSION
RUN --mount=type=bind,source=.cache/ideavim,target=/tmp/ideavim-cache \
  data_dir="$(jq -er '.dataDirectoryName' "$HOME"/.cache/JetBrains/RemoteDev/dist/*/product-info.json)" \
  && mkdir -p "$HOME/.local/share/JetBrains/$data_dir/plugins" \
  && unzip -q "/tmp/ideavim-cache/ideavim-${IDEAVIM_VERSION}-$(uname -m)" \
    -d "$HOME/.local/share/JetBrains/$data_dir/plugins"

# Tools installed to /usr/local as root
USER root

# Node.js
ARG NODE_VERSION
RUN --mount=type=bind,source=.cache/node,target=/tmp/node-cache \
  tar -xf "/tmp/node-cache/node-${NODE_VERSION}-$(uname -m)" -C /usr/local --strip-components=1

# AWS CLI v2
ARG AWSCLI_VERSION
RUN --mount=type=bind,source=.cache/awscli,target=/tmp/awscli-cache \
  unzip -q "/tmp/awscli-cache/awscli-${AWSCLI_VERSION}-$(uname -m)" -d /tmp \
  && /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli \
  && rm -rf /tmp/aws

# GitHub CLI (official release binary)
ARG GH_VERSION
RUN --mount=type=bind,source=.cache/gh,target=/tmp/gh-cache \
  tar -xf "/tmp/gh-cache/gh-${GH_VERSION}-$(uname -m)" \
    -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_$(dpkg --print-architecture)/bin/gh"

# tailcat (SSH ProxyCommand transport over Tailscale)
ARG TAILCAT_VERSION
RUN --mount=type=bind,source=.cache/tailcat,target=/tmp/tailcat-cache \
  tar -xf "/tmp/tailcat-cache/tailcat-${TAILCAT_VERSION}-$(uname -m)" -C /usr/local/bin tailcat

# Agent CLIs from npm (versions pinned in the generated package.json)
# Allow the install scripts that copilot and opencode depend on; npm 12 blocks them by default.
RUN --mount=type=cache,id=npm-cache,sharing=locked,target=/root/.npm \
  --mount=type=bind,source=package.json,target=/tmp/package.json \
  jq -r '.dependencies | to_entries[] | "\(.key)@\(.value)"' /tmp/package.json \
  | NPM_CONFIG_UPDATE_NOTIFIER=false xargs npm install -g --allow-scripts=opencode-ai,@github/keytar,node-pty

USER $USERNAME

# The agent CLIs below install as <name>.real; the local-bin wrappers copied
# afterwards take over the plain names and exec the .real binaries.

# Claude Code (native installer)
ARG CLAUDE_CODE_VERSION
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_VERSION" \
  && mv ~/.local/bin/claude ~/.local/bin/claude.real

# Cursor CLI (release advertised by the official installer)
ARG CURSOR_CLI_VERSION
RUN --mount=type=bind,source=.cache/cursor-cli,target=/tmp/cursor-cli-cache \
  cursor_dir="$HOME/.local/share/cursor-agent/versions/$CURSOR_CLI_VERSION" \
  && mkdir -p "$cursor_dir" \
  && tar -xf "/tmp/cursor-cli-cache/cursor-cli-${CURSOR_CLI_VERSION}-$(uname -m)" \
    -C "$cursor_dir" --strip-components=1 \
  && ln -s "$cursor_dir/cursor-agent" ~/.local/bin/agent \
  && ln -s "$cursor_dir/cursor-agent" ~/.local/bin/cursor-agent.real

# Antigravity CLI (pinned release, self-updates via `agy update`)
ARG ANTIGRAVITY_VERSION
RUN --mount=type=bind,source=.cache/antigravity,target=/tmp/antigravity-cache \
  tar -xf "/tmp/antigravity-cache/antigravity-${ANTIGRAVITY_VERSION}-$(uname -m)" -C /tmp antigravity \
  && mv /tmp/antigravity ~/.local/bin/agy.real

COPY --chown=$USERNAME:$USERNAME --chmod=755 local-bin/ /home/$USERNAME/.local/bin/

# Fail the build if any installed CLI, or its wrapper, cannot start.
RUN for tool in node aws gh step tailcat codex gemini copilot opencode claude cursor-agent agy; do \
    "$tool" --version; \
  done

# Switch back to root for downstream images; run with `docker run --user coder`
# for the non-root user.
USER root

ENV EDITOR=nvi

RUN install -d -o "$USERNAME" -g "$USERNAME" /projects /repos

ENTRYPOINT ["/entrypoint.sh"]
# Keep the container running when no command is supplied.
CMD ["sleep", "infinity"]

# Keep the resolved versions in the image even after workflow artifacts expire.
COPY versions.json /usr/local/share/devcontainer/versions.json
