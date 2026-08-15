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

# Where updates come from afterwards.
#
# Written on first install rather than shipped as a file in the package, so a
# .deb somebody downloaded by hand from the releases page turns into a machine
# that gets upgrades by the ordinary route. Nothing here self-updates: /opt/caelo
# and the units belong to the package manager, and an application that rewrote
# them from underneath itself would break the next apt upgrade.
#
# The key goes in /usr/share/keyrings and is named by signed-by rather than added
# to the global trusted set: apt-key would let this key sign anything on the
# machine, which is far more authority than a VPN client needs.
if command -v apt-get >/dev/null 2>&1 && [ ! -f /etc/apt/sources.list.d/caelo.list ]; then
    if command -v curl >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
        install -d /usr/share/keyrings
        if curl -fsSL https://teamgdb.github.io/Caelo/caelo-archive-key.asc \
             | gpg --dearmor -o /usr/share/keyrings/caelo-archive-keyring.gpg 2>/dev/null; then
            printf 'deb [signed-by=/usr/share/keyrings/caelo-archive-keyring.gpg] %s stable main\n' \
                'https://teamgdb.github.io/Caelo/deb' > /etc/apt/sources.list.d/caelo.list
            echo "Caelo: upgrades will come from apt."
        else
            # Not a failure of the installation. Somebody offline, or behind
            # something that blocks this, still has a working Caelo.
            rm -f /usr/share/keyrings/caelo-archive-keyring.gpg
            echo "Caelo: could not fetch the archive key; upgrades will not come from apt."
        fi
    fi
fi

if command -v rpm >/dev/null 2>&1 && [ ! -f /etc/yum.repos.d/caelo.repo ] && [ -d /etc/yum.repos.d ]; then
    cat > /etc/yum.repos.d/caelo.repo <<'REPO'
[caelo]
name=Caelo
baseurl=https://teamgdb.github.io/Caelo/rpm
enabled=1
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://teamgdb.github.io/Caelo/caelo-archive-key.asc
REPO
    echo "Caelo: upgrades will come from dnf."
fi

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
    # The socket, not the service. Nothing runs as root until somebody connects
    # to it, and the service exits again once the tunnel is down.
    systemctl enable --now caelo.socket || true
fi

exit 0
