#!/usr/bin/env bash

set -euo pipefail

# Assert databricks CLI is not already installed
if which databricks >/dev/null 2>&1; then
    exit 1
else
    exit 0
fi