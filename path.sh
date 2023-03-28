#!/usr/bin/env bash

set -e

dir="$PWD/.bin/bricks"

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

chmod +x $dir/bricks
echo "$dir" >> $GITHUB_PATH
