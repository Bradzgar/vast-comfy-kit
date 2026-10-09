#!/usr/bin/env bash
# Start (or restart) the XFCE desktop over VNC + noVNC. Idempotent.
# VNC :1 -> 127.0.0.1:5901 (localhost only, no auth needed behind the tunnel).
# noVNC -> 127.0.0.1:6080  (open http://localhost:6080/vnc.html through the SSH tunnel).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

GEO="${VNC_GEOMETRY:-1920x1080}"
DEPTH="${VNC_DEPTH:-24}"

command -v vncserver >/dev/null 2>&1 || { warn "vncserver not found; run setup-desktop.sh first"; exit 0; }

if ! pgrep -x Xtigervnc >/dev/null 2>&1; then
  log "starting VNC display :1 ($GEO)"
  vncserver :1 -geometry "$GEO" -depth "$DEPTH" -localhost -SecurityTypes None
else
  log "VNC already running"
fi

if ! pgrep -x websockify >/dev/null 2>&1; then
  log "starting noVNC/websockify on 127.0.0.1:6080"
  setsid websockify --web=/usr/share/novnc 6080 127.0.0.1:5901 \
    >"$WORKSPACE/websockify.log" 2>&1 < /dev/null &
  sleep 2
else
  log "websockify already running"
fi

log "desktop ready -> http://localhost:6080/vnc.html  (via SSH tunnel)"
