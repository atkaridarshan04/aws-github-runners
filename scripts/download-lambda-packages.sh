#!/usr/bin/env bash
# Downloads the Lambda zip releases matching a terraform-aws-github-runner module
# version — the module's Lambda code is distributed as release assets, not
# vendored into the module. Version must match the module version pinned in
# terraform/variables.tf (runner_module_version) exactly.
set -euo pipefail

VERSION="${1:?Usage: scripts/download-lambda-packages.sh <module-version, e.g. 7.11.0>}"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform/lambda-packages"
mkdir -p "$DEST"

for pkg in webhook runners runner-binaries-syncer; do
  curl -fL -o "$DEST/${pkg}.zip" \
    "https://github.com/github-aws-runners/terraform-aws-github-runner/releases/download/v${VERSION}/${pkg}.zip"
done

echo "Downloaded lambda packages for v${VERSION} into $DEST"
