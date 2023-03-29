#!/usr/bin/env bash

set -e

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
  gh run list -b main -w release-snapshot --json 'databaseId,conclusion' |
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
