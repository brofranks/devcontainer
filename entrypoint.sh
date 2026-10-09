#!/bin/bash
set -euo pipefail

export WORKSPACE_DIR="${WORKSPACE_DIR:-/work}"

# `sshd -i` has no peer address, so resolve its audit hostname locally instead of via DNS.
if ! grep -qwF UNKNOWN /etc/hosts; then
  echo "127.0.0.1 UNKNOWN" | sudo tee -a /etc/hosts > /dev/null
fi

rm -f "$HOME/.ssh/known_hosts"

if [ -n "${BOX_SSH_PUBKEY:-}" ]; then
  mkdir -p "$HOME/.ssh"
  grep -qsF "$BOX_SSH_PUBKEY" "$HOME/.ssh/authorized_keys" \
    || echo "$BOX_SSH_PUBKEY" >> "$HOME/.ssh/authorized_keys"
fi

if [ -n "${ENABLE_IDEA:-}" ]; then
  mkdir -p /tmp/logs

  cat > /tmp/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
logfile=/tmp/logs/supervisord.log
pidfile=/tmp/supervisord.pid
childlogdir=/tmp/logs

[program:remote-dev-server]
command=/bin/bash -lc 'exec "$HOME"/.cache/JetBrains/RemoteDev/dist/*/bin/remote-dev-server.sh run "$WORKSPACE_DIR"'
autorestart=false
stopsignal=TERM
stopasgroup=true
killasgroup=true
redirect_stderr=true
stdout_logfile=/tmp/logs/remote-dev-server.log
EOF

  exec /usr/bin/supervisord -c /tmp/supervisord.conf
fi

# Keep explicit commands in the foreground for TTY compatibility.
exec "$@"
