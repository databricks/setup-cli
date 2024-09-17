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

# Change into temporary directory.
cd "$RUNNER_TEMP"

# Download release archive.
curl -L -s -O "${REGISTRY_URL}databricks/cli/releases/download/v${VERSION}/${FILE}.zip"

# Unzip release archive.
unzip -q "${FILE}.zip" -d .bin

# Add databricks to path.
dir=$PWD/.bin
chmod +x "${dir}/databricks"
echo "$dir" >> "$GITHUB_PATH"
