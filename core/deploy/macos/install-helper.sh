#!/bin/bash
#
# Installs (or removes) the Caelo privileged helper.
#
#   sudo ./deploy/macos/install-helper.sh install
#   sudo ./deploy/macos/install-helper.sh uninstall
#
# The helper runs as root under launchd and does the two things a sandboxed
# application cannot: create a utun interface and change the machine's routing.
#
# This is the development path. What ships is a NetworkExtension, where the
# system owns the tunnel and no part of Caelo runs as root at all. A permanently
# resident root daemon is a real cost, and it should not outlive the reason for
# it.
set -euo pipefail

LABEL="team.gdb.caelo.helper"
HELPER_DIR="/Library/PrivilegedHelperTools"
HELPER="$HELPER_DIR/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SOCKET="/var/run/caelo-helper.sock"
LOG="/var/log/caelo-helper.log"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "error: run this with sudo" >&2
  exit 1
fi

# SUDO_UID is the user who invoked sudo — the one whose app should be allowed to
# talk to the helper. Falling back to the console owner covers being run from a
# root shell.
OWNER_UID="${SUDO_UID:-$(stat -f %u /dev/console)}"

stop_existing() {
  launchctl bootout "system/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
}

case "${1:-}" in
  install)
    if [[ ! -x "$ROOT/build/caelo-helper" ]]; then
      echo "error: build/caelo-helper is missing — run 'make helper' first" >&2
      exit 1
    fi

    echo "==> Stopping any previous helper"
    stop_existing

    echo "==> Installing the helper for uid $OWNER_UID"
    install -d -m 755 -o root -g wheel "$HELPER_DIR"
    install -m 544 -o root -g wheel "$ROOT/build/caelo-helper" "$HELPER"

    # Root-owned and not writable by anyone else. A helper binary that its own
    # user could overwrite would be a way to become root, not a way to avoid
    # asking for it.
    sed "s|__ALLOWED_UID__|$OWNER_UID|" "$HERE/$LABEL.plist" > "$PLIST"
    chown root:wheel "$PLIST"
    chmod 644 "$PLIST"

    echo "==> Starting"
    launchctl bootstrap system "$PLIST"

    for _ in $(seq 1 20); do
      [[ -S "$SOCKET" ]] && break
      sleep 0.25
    done

    if [[ -S "$SOCKET" ]]; then
      echo "==> Installed. Socket: $SOCKET, log: $LOG"
    else
      echo "error: the helper started but never created its socket — see $LOG" >&2
      exit 1
    fi
    ;;

  uninstall)
    echo "==> Stopping the helper"
    stop_existing
    # Removing the binary before the plist would leave launchd with a job it
    # cannot start, which it complains about at every boot.
    rm -f "$PLIST" "$HELPER" "$SOCKET"
    echo "==> Removed. Routing is restored by the helper as it stops."
    ;;

  *)
    echo "usage: sudo $0 install|uninstall" >&2
    exit 2
    ;;
esac
