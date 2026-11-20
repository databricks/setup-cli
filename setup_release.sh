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

# Map RUNNER_ARCH to @actions/tool-cache architecture naming (os.arch() format).
tool_cache_arch=""
case $RUNNER_ARCH in
X64)
    tool_cache_arch="x64"
    ;;
ARM64)
    tool_cache_arch="arm64"
    ;;
X86)
    tool_cache_arch="ia32"
    ;;
ARM)
    tool_cache_arch="arm"
    ;;
esac

# Check cache eligibility: exact version (X.Y.Z), valid arch, and RUNNER_TOOL_CACHE set.
use_cache=false
cache_dir=""
if [ -n "${RUNNER_TOOL_CACHE:-}" ] && [ -n "$tool_cache_arch" ] && [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    use_cache=true
    cache_dir="${RUNNER_TOOL_CACHE}/databricks/${VERSION}/${tool_cache_arch}"
fi

binary_name="databricks"
if [ "$RUNNER_OS" = Windows ]; then
    binary_name="databricks.exe"
fi

cache_is_usable() {
    [ -f "$cache_dir/$binary_name" ] &&
        [ -s "$cache_dir/$binary_name" ] &&
        [ -r "$cache_dir/$binary_name" ] &&
        { [ "$RUNNER_OS" = Windows ] || [ -x "$cache_dir/$binary_name" ]; } &&
        [ -f "${cache_dir}.complete" ]
}

if [ "$use_cache" = true ] && cache_is_usable; then
    echo "Cache hit for Databricks CLI version ${VERSION}"
    echo "$cache_dir" >> "$GITHUB_PATH"
    exit 0
fi

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

unzip -q "${FILE}.zip" -d "$dir/bin"
chmod +x "$dir/bin/$binary_name"
install_dir="$dir/bin"

cache_lock="${cache_dir}.lock"
if [ "$use_cache" = true ] && mkdir -p "${cache_dir%/*}" && mkdir "$cache_lock" 2>/dev/null; then
    trap 'rm -rf "$cache_lock" || true' EXIT
    if cache_is_usable; then
        install_dir="$cache_dir"
    elif cp -R "$install_dir" "$cache_lock/staging" &&
        rm -f "${cache_dir}.complete" &&
        rm -rf "$cache_dir" &&
        mv "$cache_lock/staging" "$cache_dir" &&
        touch "${cache_dir}.complete" &&
        cache_is_usable; then
        install_dir="$cache_dir"
    else
        echo "Unable to populate the tool cache at $cache_dir; using a temporary directory instead." >&2
    fi
fi

echo "$install_dir" >> "$GITHUB_PATH"
