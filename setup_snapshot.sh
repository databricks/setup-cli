#!/usr/bin/env bash

set -euo pipefail

# Synthesize the directory name for the snapshot build.
function bricks_snapshot_directory() {
    dir="bricks"

    # Append correct os name.
    case $RUNNER_OS in
    Linux)
        dir="${dir}_linux"
        ;;
    Windows)
        dir="${dir}_windows"
        ;;
    macOS)
        dir="${dir}_darwin"
        ;;
    esac

    # Append correct arch name.
    case $RUNNER_ARCH in
    X86)
        dir="${dir}_386"
        ;;
    X64)
        dir="${dir}_amd64_v1"
        ;;
    ARM)
        dir="${dir}_arm_6"
        ;;
    ARM64)
        dir="${dir}_arm64"
        ;;
    esac

    echo $dir
}

if test -d .bin; then
  echo "Directory .bin found; assuming bricks already downloaded"
  exit 0
fi

# Default to main branch if branch is not specified.
if [ -z "$BRICKS_BRANCH" ]; then
  BRICKS_BRANCH=main
fi

# Find last successful deco build on $BRICKS_BRANCH.
last_successful_run_id=$(
  gh run list -b "$BRICKS_BRANCH" -w release-snapshot --json 'databaseId,conclusion' |
      jq 'limit(1; .[] | select(.conclusion == "success")) | .databaseId'
)
if [ -z "$last_successful_run_id" ]; then
  echo "Unable to find last successful build"
  exit 1
fi

# Determine artifact name with the right binaries for this runner.
case $RUNNER_OS in
Linux)
    artifact="bricks_linux_snapshot"
    ;;
Windows)
    artifact="bricks_windows_snapshot"
    ;;
macOS)
    artifact="bricks_darwin_snapshot"
    ;;
esac

gh run download $last_successful_run_id -n $artifact -D .bin

dir="$PWD/.bin/$(bricks_snapshot_directory)"

if [ ! -d "$dir" ]; then
    echo "Directory does not exist: $dir"
    exit 1
fi

if [ "$RUNNER_OS" == "Windows" ]; then
    (
        cd $dir
        mv ./bricks.exe ./bricks
    )
fi

# Add bricks to path.
chmod +x $dir/bricks
echo "$dir" >> $GITHUB_PATH
