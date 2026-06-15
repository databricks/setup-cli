#!/usr/bin/env bash

set -euo pipefail

# Pull latest version from VERSION file if not set.
if [ -z "${VERSION:-}" ]; then
    VERSION=$(cat "$(dirname "$0")"/VERSION)
fi

FILE="databricks_cli_$VERSION"

# Include operating system in file name.
case $RUNNER_OS in
Linux)
    FILE="${FILE}_linux"
    ;;
Windows)
    FILE="${FILE}_windows"
    ;;
macOS)
    FILE="${FILE}_darwin"
    ;;
esac

# Include architecture in file name.
case $RUNNER_ARCH in
X86)
    FILE="${FILE}_386"
;;
X64)
    FILE="${FILE}_amd64"
;;
ARM)
    FILE="${FILE}_arm"
;;
ARM64)
    FILE="${FILE}_arm64"
;;
esac

# Use a unique directory per invocation so repeated calls in the same job (and
# other tools using $RUNNER_TEMP) don't collide. $RUNNER_TEMP is emptied at the
# beginning and end of each job, so it needs no manual cleanup; see
# https://docs.github.com/en/actions/reference/workflows-and-actions/variables
dir="$(mktemp -d "$RUNNER_TEMP/databricks.XXXXXX")"
cd "$dir"

# Download release archive.
curl -fsSL -O "https://github.com/databricks/cli/releases/download/v${VERSION}/${FILE}.zip"

# Unzip release archive.
unzip -q "${FILE}.zip"

# Add databricks to path.
chmod +x "${dir}/databricks"
echo "$dir" >> "$GITHUB_PATH"
