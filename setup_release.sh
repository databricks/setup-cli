#!/usr/bin/env bash

set -euo pipefail

# Pull latest version from VERSION file if not set.
if [ -z "${VERSION:-}" ]; then
    VERSION=$(cat "$(dirname "$0")"/VERSION)
fi

# Resolve wildcard versions to actual versions (X.Y.* or X.*).
# Example: 1.14.* resolves to the latest 1.14.x version.
if [[ "$VERSION" == *"*"* ]]; then
    # Validate format: only trailing * allowed
    if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)?\.\*$ ]]; then
        echo "Error: Invalid version format '$VERSION'. Only trailing wildcards are supported: X.Y.* or X.*" >&2
        exit 1
    fi

    original_version="$VERSION"
    prefix="${VERSION%.\*}"

    # Fetch all tags from the remote repository
    tags=$(git ls-remote --tags --refs https://github.com/databricks/cli) || { echo "Error: failed to list databricks/cli tags" >&2; exit 1; }

    # Filter for strict vX.Y.Z format (no pre-releases, no suffixes)
    strict_versions=$(printf '%s\n' "$tags" | cut -f2 | sed -nE 's|^refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)$|\1|p')

    # Match versions with the prefix, preventing 1.1.* from matching 1.10.0
    prefix_re="${prefix//./\\.}"
    matching_versions=$(echo "$strict_versions" | grep -E "^${prefix_re}(\.[0-9]+)+$" || true)

    if [ -z "$matching_versions" ]; then
        echo "Error: No matching version found for '$original_version'" >&2
        exit 1
    fi

    # Sort numerically and pick the latest
    VERSION=$(echo "$matching_versions" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
    echo "Resolved version $original_version to $VERSION"
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
