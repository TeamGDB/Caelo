#!/bin/sh
#
# Run before the package's files go away, by both dpkg and rpm.
#
# The tunnel has to come down before the binary that knows how to undo it does.
# A machine left routed through an interface whose service has been deleted has
# no network and no way to work out why.
set -e

# dpkg says "remove" or "upgrade"; rpm passes the number of versions that will
# remain, so 0 means this is the last one. On an upgrade the socket is left
# alone: stopping it would drop a tunnel somebody is using to download the
# upgrade they are installing.
case "${1:-}" in
    remove|purge|0) final=yes ;;
    *)              final=no  ;;
esac

if [ "$final" = yes ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl stop caelo.service || true
    systemctl disable --now caelo.socket || true
fi

exit 0
