#!/usr/bin/env bash
#
# Puts the macOS signing identity and provisioning profiles onto a CI runner.
#
#   ./scripts/ci-macos-signing.sh setup
#   ./scripts/ci-macos-signing.sh teardown
#
# Not for a developer machine: there the certificates are already in the login
# keychain and the profiles are already installed, which is why the project can
# say CODE_SIGN_STYLE = Manual and simply work. A hosted runner starts with
# neither, which is what broke the release pipeline (#55).
#
# Everything sensitive arrives through the environment and leaves through
# teardown. Nothing is written into the repository, nothing is passed as an
# argument -- arguments are visible in the process list to everything else on the
# machine -- and nothing is echoed. The keychain lives in RUNNER_TEMP, which the
# runner destroys with itself even if teardown never runs.
#
# Expected in the environment, all base64 of the exported file:
#
#   MACOS_CERTIFICATE_P12        Developer ID Application, exported from Keychain Access
#   MACOS_CERTIFICATE_PASSWORD   the password set during that export
#   MACOS_PROVISIONING_PROFILES  base64 of a zip of the .provisionprofile files
#
# base64 because a GitHub secret is a string and a .p12 is not text. Read them
# back with: base64 --decode <<< "$SECRET" > file.p12
set -euo pipefail

KEYCHAIN="${RUNNER_TEMP:-/tmp}/caelo-signing.keychain-db"

# What this run installed, so teardown removes those and nothing else. An
# earlier version matched *.provisionprofile, which on a developer machine would
# have deleted the profiles the local build depends on -- the ones this script
# exists to substitute for.
INSTALLED="${RUNNER_TEMP:-/tmp}/caelo-installed-profiles"

# CI only. Every path here either creates state a developer machine already has
# or removes state it needs, and the failure mode of running it by hand is
# somebody's local signing setup quietly disappearing.
[[ -n "${CI:-}" ]] || {
  echo "error: this is for CI runners. On your own machine the certificates are" >&2
  echo "       already in your keychain and the profiles are already installed." >&2
  exit 2
}

# Where Xcode looks. The first is where every version from 16 onwards reads, the
# second is where older ones do; installing into both costs nothing and removes
# a class of failure that presents as "profile not found" with the profile
# plainly sitting on disk.
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

# Deliberately not a local inside setup: the trap that removes it fires after
# setup has returned, and a local is out of scope by then. Under `set -u` that
# made the trap itself fail, leaving the decoded private key on disk -- which is
# the one thing this directory exists to avoid.
WORK=""
cleanup_work() { [[ -n "$WORK" ]] && rm -rf "$WORK"; return 0; }
trap cleanup_work EXIT

setup() {
  [[ -n "${MACOS_CERTIFICATE_P12:-}" ]] || {
    echo "error: MACOS_CERTIFICATE_P12 is not set; see docs/signing.md" >&2
    exit 1
  }

  local password
  # The keychain's own password protects nothing that outlives the job -- it is
  # thrown away with the runner. It exists because security(1) requires one.
  password="$(uuidgen)"

  WORK="$(mktemp -d)"
  chmod 700 "$WORK"
  local work="$WORK"

  echo "==> Creating a keychain for this job"
  # Idempotent, so that re-running a step that failed part way through gets a
  # clean start rather than "a keychain with the same name already exists",
  # which describes the wrong problem entirely.
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p "$password" "$KEYCHAIN"
  # Long enough for a build and a notarisation, and not indefinite: a keychain
  # that never locks is one that stays unlocked through whatever runs next.
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$password" "$KEYCHAIN"

  import_identity "$work" application "$MACOS_CERTIFICATE_P12" "$MACOS_CERTIFICATE_PASSWORD"

  # There is deliberately no Developer ID Installer identity here: the release
  # ships a .dmg and no .pkg, so nothing needs one. See packaging/macos/package.sh.

  # Without this, codesign finds the key and then blocks on a UI prompt that
  # nobody is there to answer, and the job hangs until it times out rather than
  # failing with anything that explains itself.
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$password" "$KEYCHAIN" >/dev/null

  # Prepend rather than replace: dropping the system roots would leave nothing
  # able to verify the certificate chain we just imported.
  local existing
  existing="$(security list-keychains -d user | sed 's/[[:space:]]*"\(.*\)"/\1/')"
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $existing >/dev/null

  install_profiles "$work"

  echo "==> Identities available to codesign"
  # Names only. This is the one place it is worth printing anything, because the
  # failure it catches -- the wrong certificate exported, a Development identity
  # where a Developer ID was meant -- is otherwise found by reading a signature
  # on somebody's machine days later.
  local identities
  identities="$(security find-identity -v -p codesigning "$KEYCHAIN")"
  echo "$identities" | sed 's/^ *[0-9]*) [0-9A-F]* //'

  # An import can succeed and still leave nothing usable: a certificate exported
  # without its private key, or one whose chain does not reach Apple, imports
  # perfectly well and signs nothing. Failing here names the cause; letting it
  # through means an Xcode error five minutes later that does not.
  if ! grep -q '"Developer ID Application' <<< "$identities"; then
    echo "error: no Developer ID Application identity in the imported certificate." >&2
    echo "       Check the export included the private key -- the row in Keychain" >&2
    echo "       Access has to expand to show one. See docs/signing.md." >&2
    exit 1
  fi
}

import_identity() {
  local work="$1" what="$2" encoded="$3" password="$4"
  local file="$work/$what.p12"

  base64 --decode <<< "$encoded" > "$file" 2>/dev/null || true
  # macOS base64 skips characters it does not recognise rather than failing, so
  # a mangled secret decodes to plausible-looking rubbish. What actually catches
  # it is the file's own header: a .p12 is DER, and DER starts with 0x30.
  if [[ ! -s "$file" ]] || [[ "$(head -c 1 "$file" | xxd -p)" != "30" ]]; then
    echo "error: the $what secret did not decode to a .p12." >&2
    echo "       It should be the output of: base64 -i <file>.p12" >&2
    echo "       See docs/signing.md." >&2
    exit 1
  fi

  echo "==> Importing the $what identity"
  # -A is deliberately not used: it would let every tool on the machine use the
  # key. The one that needs it is named instead.
  security import "$file" -k "$KEYCHAIN" -P "$password" \
    -T /usr/bin/codesign >/dev/null
  rm -f "$file"
}

install_profiles() {
  local work="$1"

  if [[ -z "${MACOS_PROVISIONING_PROFILES:-}" ]]; then
    echo "!! no provisioning profiles; the system extension will not build" >&2
    return
  fi

  base64 --decode <<< "$MACOS_PROVISIONING_PROFILES" > "$work/profiles.zip"
  unzip -qo "$work/profiles.zip" -d "$work/profiles"

  local installed=0
  for directory in "${PROFILE_DIRS[@]}"; do
    mkdir -p "$directory"
  done

  # Named by UUID, which is the convention Xcode's own tooling follows and what
  # anyone debugging this on a real machine will expect to find.
  while IFS= read -r -d '' profile; do
    local uuid
    uuid="$(security cms -D -i "$profile" 2>/dev/null |
      plutil -extract UUID raw -o - - 2>/dev/null || true)"
    [[ -n "$uuid" ]] || { echo "!! could not read a UUID from $(basename "$profile")" >&2; continue; }
    for directory in "${PROFILE_DIRS[@]}"; do
      cp "$profile" "$directory/$uuid.provisionprofile"
      # Recorded, not matched by pattern later: teardown must remove what this
      # run put there and leave anything else alone.
      printf '%s\n' "$directory/$uuid.provisionprofile" >> "$INSTALLED"
    done
    # The name, not the file name: PROVISIONING_PROFILE_SPECIFIER in the project
    # matches on it, so a mismatch here is the whole failure.
    echo "==> Installed profile: $(security cms -D -i "$profile" 2>/dev/null |
      plutil -extract Name raw -o - - 2>/dev/null || echo "$uuid")"
    installed=$((installed + 1))
  done < <(find "$work/profiles" -name '*.provisionprofile' -print0)

  [[ $installed -gt 0 ]] || echo "!! the archive contained no .provisionprofile files" >&2
}

teardown() {
  # Never fails. It runs from an always() step, and a cleanup that can fail is a
  # cleanup that turns an already-red job into a confusing one.
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true

  if [[ -f "$INSTALLED" ]]; then
    while IFS= read -r profile; do
      rm -f "$profile" 2>/dev/null || true
    done < "$INSTALLED"
    rm -f "$INSTALLED"
  fi

  echo "==> Signing material removed"
}

case "${1:-}" in
  setup) setup ;;
  teardown) teardown ;;
  *) echo "usage: $0 {setup|teardown}" >&2; exit 2 ;;
esac
