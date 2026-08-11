#!/bin/sh
#
# Run after the package is unpacked, by both dpkg and rpm.
#
# What it sets up is who may drive the tunnel. The privileged service is
# reachable through a socket owned by the caelo group and nothing else, so the
# group is the lock and this is where it is cut.
set -e

GROUP=caelo

# Idempotent: an upgrade runs this again, and a group that already exists is
# the normal case rather than a failure.
if ! getent group "$GROUP" >/dev/null 2>&1; then
    groupadd --system "$GROUP"
fi

# Whoever ran the installer is almost always the person who will use the
# application. Adding them here is the difference between an installation that
# works and one that ends in a permission error nobody can interpret.
#
# PKEXEC_UID covers graphical installers, which do not set SUDO_USER.
INSTALLER=""
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    INSTALLER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    INSTALLER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
fi

if [ -n "$INSTALLER" ] && ! id -nG "$INSTALLER" 2>/dev/null | tr ' ' '\n' | grep -qx "$GROUP"; then
    usermod -aG "$GROUP" "$INSTALLER" || true
    echo "Caelo: added $INSTALLER to the $GROUP group."
    echo "Caelo: log out and back in for that to take effect."
fi

if [ -z "$INSTALLER" ]; then
    echo "Caelo: could not tell who is installing this."
    echo "Caelo: run 'sudo usermod -aG $GROUP <user>' for whoever will use it."
fi

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
    # The socket, not the service. Nothing runs as root until somebody connects
    # to it, and the service exits again once the tunnel is down.
    systemctl enable --now caelo.socket || true
fi

exit 0
