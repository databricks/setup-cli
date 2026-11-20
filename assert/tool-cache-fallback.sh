#!/usr/bin/env bash

set -euo pipefail

setup_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'chmod -R u+w "$test_dir"; rm -rf "$test_dir"' EXIT

export VERSION="${VERSION:-$(cat "$setup_dir/VERSION")}"
export RUNNER_TOOL_CACHE="$test_dir/cache"
export RUNNER_TEMP="$test_dir/temp"
export GITHUB_PATH="$test_dir/path"

case "$RUNNER_ARCH" in
    X64) arch="x64" ;;
    ARM64) arch="arm64" ;;
    X86) arch="ia32" ;;
    ARM) arch="arm" ;;
    *) echo "Unknown RUNNER_ARCH: $RUNNER_ARCH" >&2; exit 1 ;;
esac

cache_version_dir="$RUNNER_TOOL_CACHE/databricks/$VERSION"
cache_dir="$cache_version_dir/$arch"
mkdir -p "$cache_dir" "$RUNNER_TEMP"
printf 'incomplete cache\n' > "$cache_dir/databricks"
chmod -R a-w "$cache_version_dir"

# Ensure the test actually exercises failed cleanup (root can bypass permissions).
if [ -w "$cache_version_dir" ] || [ -w "$cache_dir" ]; then
    echo "This test requires an unprivileged user and POSIX file permissions." >&2
    exit 1
fi

bash "$setup_dir/setup_release.sh"

install_dir="$(cat "$GITHUB_PATH")"
if [[ "$install_dir" != "$RUNNER_TEMP"/databricks.* ]]; then
    echo "Expected an installation in RUNNER_TEMP, got: $install_dir" >&2
    exit 1
fi

if [ -e "${cache_dir}.complete" ] || [ "$(cat "$cache_dir/databricks")" != "incomplete cache" ]; then
    echo "The read-only stale cache was unexpectedly modified." >&2
    exit 1
fi

"$install_dir/databricks" version
echo "Read-only stale cache fallback passed."
