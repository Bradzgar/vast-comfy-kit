#!/usr/bin/env bash
# Idempotent install of a lightweight remote desktop: XFCE + TigerVNC + noVNC.
# VNC/noVNC are bound to localhost and reached ONLY through the SSH tunnel.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "=== setup-desktop ==="

if command -v startxfce4 >/dev/null 2>&1 && command -v websockify >/dev/null 2>&1; then
  log "desktop + vnc already installed"
else
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal dbus-x11 \
    tigervnc-standalone-server tigervnc-common \
    novnc websockify xterm
fi

mkdir -p /root/.vnc
cat > /root/.vnc/xstartup <<'XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTART
chmod +x /root/.vnc/xstartup

log "=== setup-desktop done (run start-desktop.sh to launch it) ==="
