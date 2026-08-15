#!/usr/bin/env bash
#
# Builds signed apt and dnf repositories from the packages of one release.
#
#   ./scripts/make-repo.sh <artifact-dir> <pages-dir>
#
# One version, not a history. `apt upgrade` compares what is available against
# what is installed and does not care that only one is on offer, so carrying old
# releases would buy nothing and cost the whole question of when to prune -- with
# GitHub Pages holding a soft gigabyte and these packages running to tens of
# megabytes each. Somebody who wants an older version has the releases page.
#
# The packages live in the Pages tree rather than being pointed at from it: apt
# resolves the Filename field relative to the archive root and cannot be sent
# elsewhere. That is also why this cannot simply reference the release assets.
#
# Signing key comes from REPO_GPG_KEY, armoured, in the environment. Without it
# the repositories are built unsigned, which apt will refuse to install from --
# and that is the right failure, because an unsigned package repository serving a
# VPN client is worth less than none.
set -euo pipefail

ARTIFACTS="${1:?usage: make-repo.sh <artifact-dir> <pages-dir>}"
PAGES="${2:-pages}"

DEB="$(find "$ARTIFACTS" -maxdepth 2 -name '*.deb' | head -1)"
RPM="$(find "$ARTIFACTS" -maxdepth 2 -name '*.rpm' | head -1)"

GPG_HOME=""
KEY_ID=""

cleanup() { [[ -n "$GPG_HOME" ]] && rm -rf "$GPG_HOME"; return 0; }
trap cleanup EXIT

if [[ -n "${REPO_GPG_KEY:-}" ]]; then
  # Its own keyring in a temporary directory: importing into whatever GNUPGHOME
  # the runner has would leave the signing key in a place nothing here cleans up.
  GPG_HOME="$(mktemp -d)"
  chmod 700 "$GPG_HOME"
  printf '%s\n' "$REPO_GPG_KEY" | GNUPGHOME="$GPG_HOME" gpg --batch --quiet --import
  KEY_ID="$(GNUPGHOME="$GPG_HOME" gpg --list-secret-keys --with-colons |
    awk -F: '/^sec:/ {print $5; exit}')"
  [[ -n "$KEY_ID" ]] || { echo "error: REPO_GPG_KEY has no secret key" >&2; exit 1; }
  echo "==> Signing as $KEY_ID"
else
  echo "!! REPO_GPG_KEY is not set; the repositories will be unsigned and apt will refuse them" >&2
fi

sign_detached() {
  [[ -n "$KEY_ID" ]] || return 0
  GNUPGHOME="$GPG_HOME" gpg --batch --yes --armor --detach-sign \
    --local-user "$KEY_ID" --output "$2" "$1"
}

# --- apt ---------------------------------------------------------------------

if [[ -n "$DEB" ]]; then
  echo "==> apt"
  POOL="$PAGES/deb/pool/main"
  DIST="$PAGES/deb/dists/stable/main/binary-amd64"
  mkdir -p "$POOL" "$DIST"
  cp "$DEB" "$POOL/"

  # Paths in Packages are relative to the archive root, which is $PAGES/deb.
  ( cd "$PAGES/deb" && apt-ftparchive packages pool > dists/stable/main/binary-amd64/Packages )
  gzip -9 -k -f "$DIST/Packages"

  ( cd "$PAGES/deb" && apt-ftparchive \
      -o APT::FTPArchive::Release::Origin=Caelo \
      -o APT::FTPArchive::Release::Label=Caelo \
      -o APT::FTPArchive::Release::Suite=stable \
      -o APT::FTPArchive::Release::Codename=stable \
      -o APT::FTPArchive::Release::Architectures=amd64 \
      -o APT::FTPArchive::Release::Components=main \
      release dists/stable > dists/stable/Release )

  if [[ -n "$KEY_ID" ]]; then
    # Both forms. InRelease is what modern apt fetches; Release.gpg is what
    # older releases still look for, and serving only one of them turns a
    # working machine into a broken one on upgrade day.
    GNUPGHOME="$GPG_HOME" gpg --batch --yes --clearsign --local-user "$KEY_ID" \
      --output "$PAGES/deb/dists/stable/InRelease" "$PAGES/deb/dists/stable/Release"
    sign_detached "$PAGES/deb/dists/stable/Release" "$PAGES/deb/dists/stable/Release.gpg"
  fi

  # The public half, for the keyring the postinst installs.
  if [[ -n "$KEY_ID" ]]; then
    GNUPGHOME="$GPG_HOME" gpg --batch --yes --export --armor "$KEY_ID" \
      > "$PAGES/caelo-archive-key.asc"
  fi
else
  echo "!! no .deb; skipping apt" >&2
fi

# --- dnf ---------------------------------------------------------------------

if [[ -n "$RPM" ]]; then
  echo "==> dnf"
  RPMDIR="$PAGES/rpm"
  mkdir -p "$RPMDIR"
  cp "$RPM" "$RPMDIR/"

  createrepo_c --quiet "$RPMDIR"
  sign_detached "$RPMDIR/repodata/repomd.xml" "$RPMDIR/repodata/repomd.xml.asc"
else
  echo "!! no .rpm; skipping dnf" >&2
fi

echo "==> $PAGES/deb and $PAGES/rpm"
