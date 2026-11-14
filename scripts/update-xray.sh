#!/usr/bin/env bash
# Moves the core to another Xray-core release.
#
#   scripts/update-xray.sh v26.11.9
#
# Xray tags its releases v26.11.9, but its go.mod has no /v26 suffix, so Go
# will not take the tag by name. The tag's commit is resolved here and pinned
# instead; go.mod then records it as a pseudo-version, and the release it came
# from is what Xray itself reports at run time (core.Version), which is what
# diagnostics show. Nothing else in the tree names the version except the
# attribution table, updated below.
#
# Then the VLESS tests run against a real Xray server built from the same
# release, so an update that changes how a link is understood fails here
# rather than on someone's phone.
set -euo pipefail

TAG="${1:-}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 vYY.M.D   (an Xray-core release tag, e.g. v26.11.9)" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO=https://github.com/XTLS/Xray-core

# An annotated tag points at a tag object; ^{} is the commit behind it.
REFS="$(git ls-remote "$REPO" "refs/tags/$TAG^{}" "refs/tags/$TAG")"
COMMIT="$(awk '/\^\{\}$/ {print $1}' <<< "$REFS")"
[[ -n "$COMMIT" ]] || COMMIT="$(awk 'NR==1 {print $1}' <<< "$REFS")"
if [[ -z "$COMMIT" ]]; then
  echo "error: $TAG is not a tag in $REPO" >&2
  exit 1
fi
echo "==> $TAG is $COMMIT"

cd "$ROOT/core"
go get "github.com/xtls/xray-core@$COMMIT"
go mod tidy

REPORTED="$(go run ./scripts/xray-version)"
if [[ "v$REPORTED" != "$TAG" ]]; then
  echo "error: the linked Xray reports $REPORTED, not $TAG" >&2
  exit 1
fi

# The attribution table names the release; keep it honest.
sed -i.bak -E "s#(\| \[Xray-core\]\(https://github.com/XTLS/Xray-core\) \| MPL-2.0 \| )v[0-9.]+#\1$TAG#" ATTRIBUTION.md "$ROOT/ATTRIBUTION.md"
rm -f ATTRIBUTION.md.bak "$ROOT/ATTRIBUTION.md.bak"

echo "==> Testing VLESS against a server from the same release"
go test ./internal/vless/... ./internal/probe/... ./internal/protocol/... ./internal/tunnel/...

echo "==> Xray-core $TAG. Review go.mod, go.sum and ATTRIBUTION.md, then build every platform."
