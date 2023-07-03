#!/usr/bin/env bash

set -euo pipefail

EXPECTED=$(cat $(dirname $0)/VERSION)
ACTUAL=$(databricks version --output json | jq -r .Version)

if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "Version \"$ACTUAL\" does not match expectation \"$EXPECTED\"."
    exit 1
else
    echo "Version \"$ACTUAL\" matches expectation."
    exit 0
fi
