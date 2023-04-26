#!/usr/bin/env bash

set -e

if test -d .bin; then
  echo "Directory .bin found; assuming bricks already downloaded"
  exit 0
fi

file="bricks_$VERSION"

# Include operating system in file name.
case $RUNNER_OS in
Linux)
    file="${file}_linux"
    ;;
Windows)
    file="${file}_windows"
    ;;
macOS)
    file="${file}_darwin"
    ;;
esac

# Include architecture in file name.
case $RUNNER_ARCH in
X86)
    file="${file}_386"
;;
X64)
    file="${file}_amd64"
;;
ARM)
    file="${file}_arm"
;;
ARM64)
    file="${file}_arm64"
;;
esac

# Download bricks release archive.
curl -s -O https://databricks-bricks.s3.amazonaws.com/v$VERSION/$file.zip

# Unzip bricks release archive.
unzip $file.zip -d .bin -q

# Add bricks to path.
dir=$PWD/.bin
chmod +x $dir/bricks
echo "$dir" >> $GITHUB_PATH
