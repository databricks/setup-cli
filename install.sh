#!/bin/sh

# Note: we cannot assume we're running bash and use the set -euo pipefail approach.
set -e

VERSION="1.26.0"
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
curl -fsSL -O "https://github.com/databricks/cli/releases/download/v${VERSION}/${FILE}.zip"

# Download and verify checksum.
curl -fsSL -O "https://github.com/databricks/cli/releases/download/v${VERSION}/databricks_cli_${VERSION}_SHA256SUMS"

# Determine which checksum tool to use.
CHECKSUM_TOOL=""
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
chmod +x ./databricks
cp ./databricks "$TARGET"
echo "Installed $("$TARGET/databricks" -v) at $TARGET/databricks."

# Clean up temporary directory.
cd "$OLDPWD"
rm -rf "$tmpdir" || true
