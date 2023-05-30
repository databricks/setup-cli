#!/bin/sh

set -e

VERSION="0.100.2"
FILE="databricks_cli_$VERSION"

# Include operating system in file name.
OS="$(uname -s)"
case "$OS" in
Linux)
    FILE="${FILE}_linux"
    TARGET="/usr/local/bin"
    ;;
Darwin)
    FILE="${FILE}_darwin"
    TARGET="/usr/local/bin"
    ;;
*)
    echo "Unknown operating system: $OS"
    exit 1
    ;;
esac

# Include architecture in file name.
ARCH="$(uname -m)"
case "$ARCH" in
i386)
    FILE="${FILE}_386"
    ;;
x86_64)
    FILE="${FILE}_amd64"
    ;;
arm)
    FILE="${FILE}_arm"
    ;;
arm64)
    FILE="${FILE}_arm64"
    ;;
*)
    echo "Unknown architecture: $ARCH"
    exit 1
    ;;
esac

# Make sure the target directory is writable.
if [ ! -w "$TARGET" ]; then
    echo "Target directory $TARGET is not writable."
    echo "Please run this script through sudo to allow writing to $TARGET."
    exit 1
fi

# Make sure we don't overwrite an existing installation.
if [ -f "$TARGET/databricks" ]; then
    echo "Target path $TARGET/databricks already exists."
    exit 1
fi

# Change into temporary directory.
cd "$(mktemp -d)"

# Download release archive.
curl -s -O "https://databricks-bricks.s3.amazonaws.com/v${VERSION}/${FILE}.zip"

# Unzip release archive.
unzip -q "${FILE}.zip"

# Add databricks to path.
chmod +x ./databricks
cp ./databricks "$TARGET"
