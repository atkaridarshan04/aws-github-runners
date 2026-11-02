#!/usr/bin/env bash
# Downloads the Lambda zip releases matching the terraform-aws-github-runner module
# version pinned in terraform/main.tf -- the module's Lambda code is distributed as
# release assets, not vendored into the module. The version is read from main.tf,
# so the zips cannot drift from the module.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/terraform/lambda-packages"

VERSION="$(awk '/source *= *"github-aws-runners\/github-runner\/aws"/ {found=1} found && /version *=/ {gsub(/[^0-9.]/, "", $3); print $3; exit}' "$ROOT/terraform/main.tf")"
[ -n "$VERSION" ] || { echo "Could not read the module version from terraform/main.tf" >&2; exit 1; }

mkdir -p "$DEST"

for pkg in webhook runners runner-binaries-syncer; do
  curl -fL -o "$DEST/${pkg}.zip" \
    "https://github.com/github-aws-runners/terraform-aws-github-runner/releases/download/v${VERSION}/${pkg}.zip" \
    || { echo "Failed to download ${pkg}.zip for v${VERSION}" >&2; exit 1; }
done

echo "Downloaded lambda packages for v${VERSION} into $DEST"
