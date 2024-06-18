#!/usr/bin/env bash

set -euo pipefail

function list_files() {
    find . -not -path '.' -not -path './setup-cli*'
}

# The ./setup-cli path is expected to be present.
if [[ "$(list_files)" != "" ]]; then
    echo "Found unexpected files in working directory:"
    list_files
    exit 1
else
    exit 0
fi
