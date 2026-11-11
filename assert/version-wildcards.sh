#!/usr/bin/env bash

set -euo pipefail

setup_script="$(cd "$(dirname "$0")/.." && pwd)/setup_release.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/setup-cli-wildcards.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/fixture" "$test_dir/runner"
: > "$test_dir/path"

printf '#!/bin/sh\nexit 0\n' > "$test_dir/fixture/databricks"
(
    cd "$test_dir/fixture"
    zip -q "$test_dir/fixture.zip" databricks
)
if command -v sha256sum > /dev/null 2>&1; then
    checksum_output=$(sha256sum "$test_dir/fixture.zip")
else
    checksum_output=$(shasum -a 256 "$test_dir/fixture.zip")
fi
archive_hash="${checksum_output%% *}"

cat > "$test_dir/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_GIT_CALLS"
if [ "$*" != "ls-remote --tags --refs https://github.com/databricks/cli" ]; then
    echo "Unexpected git invocation: $*" >&2
    exit 1
fi
if [ "$MOCK_GIT_STATUS" != 0 ]; then
    echo "Mock git transport failure" >&2
    exit "$MOCK_GIT_STATUS"
fi
printf '%s\n' "$MOCK_TAGS"
EOF

cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
printf '%s\n' "$url" >> "$MOCK_DOWNLOADS"
asset="${url##*/}"
case "$asset" in
    databricks_cli_*_linux_amd64.zip)
        cp "$MOCK_ARCHIVE" "$asset"
        ;;
    databricks_cli_*_SHA256SUMS)
        printf '%s  %s_linux_amd64.zip\n' "$MOCK_ARCHIVE_HASH" "${asset%_SHA256SUMS}" > "$asset"
        ;;
    *)
        echo "Unexpected download: $url" >&2
        exit 1
        ;;
esac
EOF

chmod +x "$test_dir/bin/"*

tags() {
    local tag
    for tag in "$@"; do
        printf '0123456789abcdef0123456789abcdef01234567\trefs/tags/%s\n' "$tag"
    done
}

run_setup() {
    : > "$test_dir/git-calls"
    : > "$test_dir/downloads"
    status=0
    env -i \
        PATH="$test_dir/bin:$PATH" \
        LC_ALL=C \
        VERSION="$1" \
        MOCK_TAGS="$2" \
        MOCK_GIT_STATUS="${3:-0}" \
        MOCK_GIT_CALLS="$test_dir/git-calls" \
        MOCK_DOWNLOADS="$test_dir/downloads" \
        MOCK_ARCHIVE="$test_dir/fixture.zip" \
        MOCK_ARCHIVE_HASH="$archive_hash" \
        RUNNER_OS=Linux \
        RUNNER_ARCH=X64 \
        RUNNER_TEMP="$test_dir/runner" \
        GITHUB_PATH="$test_dir/path" \
        bash "$setup_script" > "$test_dir/stdout" 2> "$test_dir/stderr" || status=$?
}

expect_version() {
    run_setup "$1" "$2"
    if [ "$status" != 0 ]; then
        cat "$test_dir/stderr" >&2
        exit 1
    fi
    local expected_archive="https://github.com/databricks/cli/releases/download/v${3}/databricks_cli_${3}_linux_amd64.zip"
    local expected_checksum="https://github.com/databricks/cli/releases/download/v${3}/databricks_cli_${3}_SHA256SUMS"
    local downloads
    downloads=$(cat "$test_dir/downloads")
    if [ "$downloads" != "$expected_archive" ] &&
        [ "$downloads" != "$(printf '%s\n%s' "$expected_archive" "$expected_checksum")" ]; then
        echo "Expected $expected_archive and optionally $expected_checksum; got $downloads" >&2
        exit 1
    fi
}

expect_failure() {
    run_setup "$1" "$2" "${4:-0}"
    if [ "$status" = 0 ]; then
        echo "Expected resolution failure for '$1'" >&2
        exit 1
    fi
    grep -F -- "$3" "$test_dir/stderr" > /dev/null
    if [ -s "$test_dir/downloads" ]; then
        echo "Resolution failure attempted a download" >&2
        exit 1
    fi
}

fixtures=$(tags v1.2.2 v1.2.9 v1.2.10 v1.20.99 v2.0.0 \
    v1.2.999-rc.1 v1.2.999+build 1.2.999 v1.2.999.0 'v1.2.999^{}')
expect_version '1.2.*' "$fixtures" 1.2.10
expect_version '1.*' "$fixtures" 1.20.99
expect_version '1.1.*' "$(tags v1.1.2 v1.10.99)" 1.1.2
expect_version '1.*' "$(tags v1.9.99 v1.10.2)" 1.10.2

for invalid in '*' '1.*.3' 'v1.*' '1.[2].*' '1.2.*; false'; do
    expect_failure "$invalid" "$fixtures" "Invalid version format"
    test ! -s "$test_dir/git-calls"
done

expect_failure '9.*' "$fixtures" "No matching version found for '9.*'"
expect_failure '1.*' '' "No matching version found for '1.*'"
expect_failure '1.*' "$(tags v1.2.999-rc.1 1.2.999)" "No matching version found for '1.*'"
expect_failure '1.*' "$fixtures" "failed to list databricks/cli tags" 1

expect_version '1.2.2' '' 1.2.2
test ! -s "$test_dir/git-calls"
expect_version '' '' "$(cat "$(dirname "$setup_script")/VERSION")"
test ! -s "$test_dir/git-calls"

expect_version '1.2.*' "$(tags v1.2.2)" 1.2.2
first_path=$(tail -n 1 "$test_dir/path")
expect_version '1.2.*' "$(tags v1.2.2 v1.2.3)" 1.2.3
second_path=$(tail -n 1 "$test_dir/path")
test "$first_path" != "$second_path"
test -x "$first_path/databricks"
test -x "$second_path/databricks"

echo "Offline wildcard resolution assertions passed."
