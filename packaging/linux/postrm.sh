#!/bin/sh
#
# Run after the package's files have gone, by both dpkg and rpm.
set -e

case "${1:-}" in
    purge|remove|0) final=yes ;;
    *)              final=no  ;;
esac

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
fi

# The group is left behind on purpose. Removing it would strip membership from
# every account that had it, and reinstalling would not put it back: someone
# who removes the package to install a newer build would find themselves
# locked out of their own VPN with no indication why.
#
# Deleting a group also silently frees its gid for reuse, which is how files
# owned by a group that no longer exists end up belonging to a different one.
if [ "$final" = yes ]; then
    echo "Caelo: the caelo group was left in place; remove it with 'groupdel caelo' if you want it gone."
fi

exit 0
