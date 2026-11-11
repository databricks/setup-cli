#!/bin/sh

# Note: we cannot assume we're running bash and use the set -euo pipefail approach.
set -e

VERSION="1.26.0"
FILE="databricks_cli_$VERSION"

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ -z "$1" ]; }; then
    echo "Usage: sh install.sh [INSTALL_DIR]" >&2
    echo "Specify at most one non-empty installation directory." >&2
    exit 1
fi

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

# Apply installation directory overrides in order of precedence:
# 1. Positional argument (e.g., curl ... | sh -s -- ~/.local/bin)
if [ $# -gt 0 ]; then
    TARGET="$1"
# 2. DATABRICKS_CLI_INSTALL_DIR environment variable
elif [ -n "${DATABRICKS_CLI_INSTALL_DIR:-}" ]; then
    TARGET="$DATABRICKS_CLI_INSTALL_DIR"
# 3. DATABRICKS_RUNTIME_VERSION environment variable (DBR)
elif [ -n "${DATABRICKS_RUNTIME_VERSION:-}" ]; then
    TARGET="$HOME/bin"
fi

# Expand ~ and protect relative paths starting with a dash.
case "$TARGET" in
("~"|"~"/*)
    _rest="${TARGET#?}"
    TARGET="$HOME$_rest"
    ;;
esac
case "$TARGET" in
-*)
    TARGET="./$TARGET"
    ;;
esac

# Auto-create target directory; errors are caught by the writability check below.
mkdir -p "$TARGET" 2>/dev/null || true

# Reject if target exists but is not a directory.
if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
    echo "Target path $TARGET exists but is not a directory."
    exit 1
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
    echo
    echo "To choose another directory, rerun this installer with a writable path"
    echo "as its first argument, or set DATABRICKS_CLI_INSTALL_DIR (e.g., ~/.local/bin)."
    echo "To install to $TARGET, rerun this installer with permission to write there."
    exit 1
fi

TARGET="$(CDPATH='' cd -P "$TARGET" && pwd -P)"

# Make sure we don't overwrite an existing installation.
if [ -f "$TARGET/databricks" ]; then
    echo "Target path $TARGET/databricks already exists."
    echo "Please remove the existing installation first using"
    echo "  rm '$TARGET/databricks'"
    exit 1
fi

# Change into temporary directory.
tmpdir="$(mktemp -d)"
cd "$tmpdir"

# Download release archive.
curl -fsSL -O "https://github.com/databricks/cli/releases/download/v${VERSION}/${FILE}.zip"

# Unzip release archive.
unzip -q "${FILE}.zip"

# Add databricks to path.
chmod +x ./databricks
cp ./databricks "$TARGET"
echo "Installed $("$TARGET/databricks" -v) at $TARGET/databricks."

# Clean up temporary directory.
cd "$OLDPWD"
rm -rf "$tmpdir" || true
