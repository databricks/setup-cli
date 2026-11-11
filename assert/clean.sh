#!/usr/bin/env bash

set -euo pipefail

# Ignore only the checkout itself, including its contents. Capture outside the
# conditional so a failed filesystem scan fails this assertion.
files=$(find . -path './setup-cli' -prune -o -not -path '.' -print)
if [[ -n "$files" ]]; then
    echo "Found unexpected files in working directory:"
    printf '%s\n' "$files"
    exit 1
fi
