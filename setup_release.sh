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

# Download and verify checksum.
curl -fsSL -O "https://github.com/databricks/cli/releases/download/v${VERSION}/databricks_cli_${VERSION}_SHA256SUMS"

# Determine which checksum tool to use.
if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_TOOL="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_TOOL="shasum -a 256"
else
    echo "Error: Neither sha256sum nor shasum is available."
    echo "Please install one of these tools to verify checksum integrity."
    exit 1
fi

# Extract the expected checksum for this specific file.
if ! expected_hash=$(awk -v filename="${FILE}.zip" '
    $2 == filename { count++; hash = $1; fields = NF }
    END {
        if (count != 1 || fields != 2 || length(hash) != 64 || hash ~ /[^0-9a-fA-F]/) exit 1
        print tolower(hash)
    }
' "databricks_cli_${VERSION}_SHA256SUMS"); then
    echo "Error: Expected exactly one valid SHA-256 checksum for ${FILE}.zip in databricks_cli_${VERSION}_SHA256SUMS" >&2
    exit 1
fi

# Compute the actual checksum.
if ! checksum_output=$($CHECKSUM_TOOL "${FILE}.zip"); then
    echo "Error: Unable to compute SHA-256 checksum for ${FILE}.zip" >&2
    exit 1
fi
actual_hash=${checksum_output%% *}

# Verify the checksum matches.
if [ "$expected_hash" != "$actual_hash" ]; then
    echo "Error: Checksum mismatch for ${FILE}.zip"
    echo "Expected: $expected_hash"
    echo "Actual:   $actual_hash"
    exit 1
fi

# Unzip release archive.
unzip -q "${FILE}.zip"

# Add databricks to path.
chmod +x "${dir}/databricks"
echo "$dir" >> "$GITHUB_PATH"
