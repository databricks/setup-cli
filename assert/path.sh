#!/usr/bin/env bash

set -euo pipefail

EXPECTED="${1:-invalid}"
ACTUAL=$(which databricks)

if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "Path \"$ACTUAL\" does not match expectation \"$EXPECTED\"."
    exit 1
else
    echo "Path \"$ACTUAL\" matches expectation."
    exit 0
fi
