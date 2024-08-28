#!/bin/sh

# Note: we cannot assume we're running bash and use the set -euo pipefail approach.
set -e

VERSION="0.227.1"
FILE="databricks_cli_$VERSION"

# Include operating system in file name.
OS="$(uname -s | cut -d '-' -f 1)"
case "$OS" in
Linux)
    FILE="${FILE}_linux"
    TARGET="/usr/local/bin"
    ;;
Darwin)
    FILE="${FILE}_darwin"
    TARGET="/usr/local/bin"
    ;;
MINGW64_NT)
    FILE="${FILE}_windows"
    TARGET="/c/Windows"
    ;;
*)
    echo "Unknown operating system: $OS"
    exit 1
    ;;
esac

# Set target to ~/bin if DATABRICKS_RUNTIME_VERSION environment variable is set.
if [ -n "$DATABRICKS_RUNTIME_VERSION" ]; then
    # Set the installation target to ~/bin when run on DBR
    TARGET="$HOME/bin"

    # Create the target directory if it does not exist
    mkdir -p "$TARGET"
fi

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
arm64|aarch64)
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
    echo "Please run this script through 'sudo' to allow writing to $TARGET."
    echo
    echo "If you're running this script from a terminal, you can do so using"
    echo "  curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/v${VERSION}/install.sh | sudo sh"
    exit 1
fi

# Make sure we don't overwrite an existing installation.
if [ -f "$TARGET/databricks" ]; then
    echo "Target path $TARGET/databricks already exists."
    echo "If you have an existing Databricks CLI installation, please first remove it using"
    echo "  sudo rm '$TARGET/databricks'"
    exit 1
fi

# Change into temporary directory.
tmpdir="$(mktemp -d)"
cd "$tmpdir"

# Download release archive.
curl -L -s -O "https://github.com/databricks/cli/releases/download/v${VERSION}/${FILE}.zip"

# Unzip release archive.
unzip -q "${FILE}.zip"

# Add databricks to path.
chmod +x ./databricks
cp ./databricks "$TARGET"
echo "Installed $("$TARGET/databricks" -v) at $TARGET/databricks."

# Clean up temporary directory.
cd "$OLDPWD"
rm -rf "$tmpdir" || true
