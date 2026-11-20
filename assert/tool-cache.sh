#!/usr/bin/env bash

set -euo pipefail

setup_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
background_pid=""

cleanup() {
    for control in "$test_dir"/*/control; do
        if [ -d "$control" ]; then
            touch "$control/release"
        fi
    done
    if [ -n "$background_pid" ]; then
        wait "$background_pid" || true
    fi
    chmod -R u+w "$test_dir"
    rm -rf "$test_dir"
}
trap cleanup EXIT

mock_bin="$test_dir/mocks"
fixtures="$test_dir/fixtures"
mkdir -p "$mock_bin" "$fixtures"
real_cp="$(command -v cp)"
real_touch="$(command -v touch)"
host_os="${RUNNER_OS:-Linux}"
printf '#!/bin/sh\ntouch "%s"\nexit 99\n' "$test_dir/executed" > "$fixtures/databricks"
cp "$fixtures/databricks" "$fixtures/databricks.exe"

wait_for() {
    local filename="$1"
    local attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        if [ -f "$filename" ]; then
            return 0
        fi
        sleep 0.05
    done
    echo "Timed out waiting for $filename" >&2
    return 1
}
declare -f wait_for > "$test_dir/helpers.sh"

cat > "$test_dir/reader-hook.sh" <<'EOF'
if [[ "$TEST_MODE" = hold-reader ]]; then
    source "$TEST_HELPERS"
    [() {
        local predicate_result
        if builtin [ "$@"; then
            predicate_result=0
        else
            predicate_result=$?
        fi
        if [[ "$predicate_result" -eq 0 && "$#" -eq 3 &&
            "$1" = -f && "$2" = "$TEST_CACHE_DIR/$TEST_BINARY" &&
            ! -f "$TEST_CONTROL/reader-ready" ]]; then
            "$TEST_REAL_TOUCH" "$TEST_CONTROL/reader-ready"
            wait_for "$TEST_CONTROL/release"
        fi
        return "$predicate_result"
    }
fi
EOF

cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
asset="${!#}"
asset="${asset##*/}"
printf 'curl %s\n' "$asset" >> "$TEST_EVENTS"
case "$asset" in
    *.zip)
        printf 'offline archive fixture\n' > "$asset"
        ;;
    *_SHA256SUMS)
        for archive in *.zip; do
            if command -v sha256sum >/dev/null 2>&1; then
                checksum_output=$(sha256sum "$archive")
            else
                checksum_output=$(shasum -a 256 "$archive")
            fi
            # Match the published manifest even when Windows tools use binary mode.
            printf '%s  %s\n' "${checksum_output%% *}" "$archive"
        done > "$asset"
        ;;
    *)
        exit 1
        ;;
esac
EOF

cat > "$mock_bin/unzip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$TEST_HELPERS"
destination="."
while [ "$#" -gt 0 ]; do
    case "$1" in
        -d) destination="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ "$TEST_MODE" = hold-extract ]; then
    touch "$TEST_CONTROL/extract-ready"
    wait_for "$TEST_CONTROL/release"
fi
mkdir -p "$destination"
"$TEST_REAL_CP" "$TEST_FIXTURES/$TEST_BINARY" "$destination/$TEST_BINARY"
EOF

cat > "$mock_bin/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$TEST_HELPERS"
if [[ "${!#}" == *.lock/staging ]]; then
    case "$TEST_MODE" in
        hold-copy)
            touch "$TEST_CONTROL/copy-ready"
            wait_for "$TEST_CONTROL/release"
            ;;
        fail-copy)
            exit 9
            ;;
    esac
fi
exec "$TEST_REAL_CP" "$@"
EOF

cat > "$mock_bin/touch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$TEST_MODE" = fail-marker ] && [ "${!#}" = "$TEST_CACHE_DIR.complete" ]; then
    exit 9
fi
exec "$TEST_REAL_TOUCH" "$@"
EOF
chmod +x "$mock_bin"/*

new_case() {
    case_dir="$test_dir/$1"
    cache_root="$case_dir/cache with spaces"
    cache_dir="$cache_root/databricks/1.21.0/x64"
    runner_os="$host_os"
    runner_arch=X64
    binary_name="databricks"
    if [ "$runner_os" = Windows ]; then
        binary_name="databricks.exe"
    fi
    version="1.21.0"
    test_mode=""
    mkdir -p "$case_dir/control"
}

run_setup() {
    local invocation="$1"
    local mode="${2:-$test_mode}"
    mkdir -p "$case_dir/$invocation/temp with spaces"
    if ! env -i PATH="$mock_bin:$PATH" BASH_ENV="$test_dir/reader-hook.sh" \
        RUNNER_OS="$runner_os" RUNNER_ARCH="$runner_arch" VERSION="$version" \
        RUNNER_TEMP="$case_dir/$invocation/temp with spaces" \
        RUNNER_TOOL_CACHE="$cache_root" GITHUB_PATH="$case_dir/$invocation/path" \
        TEST_EVENTS="$case_dir/events" TEST_CONTROL="$case_dir/control" \
        TEST_FIXTURES="$fixtures" TEST_BINARY="$binary_name" \
        TEST_HELPERS="$test_dir/helpers.sh" TEST_MODE="$mode" \
        TEST_REAL_CP="$real_cp" TEST_REAL_TOUCH="$real_touch" TEST_CACHE_DIR="$cache_dir" \
        bash "$setup_dir/setup_release.sh" \
        > "$case_dir/$invocation/stdout" 2> "$case_dir/$invocation/stderr"; then
        cat "$case_dir/$invocation/stderr" >&2
        return 1
    fi
    touch "$case_dir/$invocation/done"
}

assert_cache() {
    [ "$(cat "$case_dir/$1/path")" = "$cache_dir" ]
    [ -f "$cache_dir.complete" ]
    cmp "$fixtures/$binary_name" "$cache_dir/$binary_name"
    [ -r "$cache_dir/$binary_name" ]
    if [ "$runner_os" != Windows ]; then
        [ -x "$cache_dir/$binary_name" ]
    fi
    [ ! -d "$cache_dir.lock" ]
}

assert_private() {
    local selected
    selected="$(cat "$case_dir/$1/path")"
    [[ "$selected" == "$case_dir/$1/temp with spaces"/databricks.* ]]
    cmp "$fixtures/$binary_name" "$selected/$binary_name"
}

new_case repeat
run_setup first
assert_cache first
touch "$cache_dir/sentinel"
run_setup second
assert_cache second
[ -f "$cache_dir/sentinel" ]
[ "$(grep -c '^curl ' "$case_dir/events")" = 2 ]
echo "PASS cache miss, usable hit, paths with spaces, no cached execution"

for state in incomplete missing empty non-executable unreadable; do
    if { [ "$state" = non-executable ] || [ "$state" = unreadable ]; } && [ "$host_os" = Windows ]; then
        continue
    fi
    new_case "$state"
    mkdir -p "$cache_dir"
    case "$state" in
        incomplete) printf 'stale\n' > "$cache_dir/$binary_name" ;;
        missing) touch "$cache_dir.complete" ;;
        empty) touch "$cache_dir/$binary_name" "$cache_dir.complete" ;;
        non-executable)
            cp "$fixtures/$binary_name" "$cache_dir/$binary_name"
            chmod a-x "$cache_dir/$binary_name"
            touch "$cache_dir.complete"
            ;;
        unreadable)
            cp "$fixtures/$binary_name" "$cache_dir/$binary_name"
            chmod a-r "$cache_dir/$binary_name"
            touch "$cache_dir.complete"
            if [ -r "$cache_dir/$binary_name" ]; then
                echo "SKIP unreadable file permissions: requires an unprivileged user"
                continue
            fi
            ;;
    esac
    run_setup repaired
    assert_cache repaired
    echo "PASS repair $state cache"
done

new_case windows
runner_os=Windows
binary_name=databricks.exe
mkdir -p "$cache_dir"
cp "$fixtures/databricks" "$cache_dir/databricks"
touch "$cache_dir.complete"
run_setup first
assert_cache first
run_setup second
assert_cache second
[ "$(grep -c '^curl ' "$case_dir/events")" = 2 ]
echo "PASS explicit Windows .exe publication and hit"

if [ "$host_os" != Windows ]; then
    new_case wrong-platform-name
    mkdir -p "$cache_dir"
    cp "$fixtures/databricks.exe" "$cache_dir/databricks.exe"
    touch "$cache_dir.complete"
    run_setup repaired
    assert_cache repaired
    echo "PASS POSIX cache requires the unsuffixed executable"
fi

new_case keys
run_setup first
assert_cache first
touch "$cache_dir/sentinel"
version="1.22.0"
cache_dir="$cache_root/databricks/$version/x64"
run_setup version
assert_cache version
runner_arch=ARM64
cache_dir="$cache_root/databricks/$version/arm64"
run_setup architecture
assert_cache architecture
[ -f "$cache_root/databricks/1.21.0/x64/sentinel" ]
[ -f "$cache_root/databricks/1.22.0/x64/$binary_name" ]
echo "PASS exact version and architecture keys remain independent"

new_case disabled
cache_root=""
run_setup disabled
assert_private disabled
new_case prerelease
version="1.21.0-rc.1"
run_setup prerelease
assert_private prerelease
[ ! -e "$cache_root" ]
echo "PASS unset cache and non-exact version fallback"

new_case abandoned-lock
mkdir -p "$cache_dir.lock"
touch "$cache_dir.lock/owner"
run_setup contender &
background_pid=$!
wait_for "$case_dir/contender/done"
wait "$background_pid"
background_pid=""
assert_private contender
[ -f "$cache_dir.lock/owner" ]
echo "PASS abandoned lock is neither waited on nor removed"

new_case contention
run_setup owner hold-copy &
background_pid=$!
wait_for "$case_dir/control/copy-ready"
run_setup contender &
contender_pid=$!
wait_for "$case_dir/contender/done"
wait "$contender_pid"
assert_private contender
[ -d "$cache_dir.lock" ]
[ ! -e "$cache_dir.complete" ]
touch "$case_dir/control/release"
wait "$background_pid"
background_pid=""
assert_cache owner
assert_private contender
echo "PASS concurrent contender falls back without deleting owner's installation"

new_case late-miss
run_setup late hold-extract &
background_pid=$!
wait_for "$case_dir/control/extract-ready"
run_setup winner
assert_cache winner
touch "$cache_dir/sentinel"
touch "$case_dir/control/release"
wait "$background_pid"
background_pid=""
assert_cache late
[ -f "$cache_dir/sentinel" ]
echo "PASS late miss rechecks completed entry after acquiring lock"

new_case staging-failure
mkdir -p "$cache_dir"
printf 'stale\n' > "$cache_dir/$binary_name"
run_setup fallback fail-copy
assert_private fallback
[ "$(cat "$cache_dir/$binary_name")" = stale ]
[ ! -d "$cache_dir.lock" ]
echo "PASS staging failure preserves shared stale entry"

new_case marker-failure
run_setup fallback fail-marker
assert_private fallback
[ ! -e "$cache_dir.complete" ]
[ ! -d "$cache_dir.lock" ]
run_setup repaired
assert_cache repaired
echo "PASS marker failure falls back and next invocation repairs entry"

new_case completed-reader
mkdir -p "$cache_dir"
touch "$cache_dir/$binary_name" "$cache_dir.complete"
run_setup reader hold-reader &
background_pid=$!
wait_for "$case_dir/control/reader-ready"
run_setup writer fail-marker
assert_private writer
[ ! -e "$cache_dir.complete" ]
mkdir "$cache_dir.lock"
touch "$cache_dir.lock/owner"
touch "$case_dir/control/release"
wait_for "$case_dir/reader/done"
wait "$background_pid"
background_pid=""
if grep -q '^Cache hit ' "$case_dir/reader/stdout"; then
    echo "ERROR: reader accepted an unpublished cache replacement" >&2
    exit 1
fi
assert_private reader
[ -f "$cache_dir.lock/owner" ]
[ ! -e "$cache_dir.complete" ]
echo "PASS completed reader rejects replacement without a completion marker"

if [ "$host_os" != Windows ]; then
    new_case readonly-usable
    run_setup first
    chmod -R a-w "${cache_dir%/*}"
    run_setup second
    assert_cache second
    [ "$(grep -c '^curl ' "$case_dir/events")" = 2 ]
    chmod -R u+w "${cache_dir%/*}"
    echo "PASS usable read-only completed entry remains a cache hit"
    for protected in parent entry; do
        new_case "readonly-$protected"
        mkdir -p "$cache_dir"
        printf 'stale\n' > "$cache_dir/$binary_name"
        protected_dir="$cache_dir"
        if [ "$protected" = parent ]; then
            protected_dir="${cache_dir%/*}"
        fi
        chmod -R a-w "$protected_dir"
        if [ -w "$protected_dir" ]; then
            echo "SKIP read-only $protected permissions: requires an unprivileged user"
        else
            run_setup fallback
            assert_private fallback
            [ "$(cat "$cache_dir/$binary_name")" = stale ]
            [ ! -d "$cache_dir.lock" ]
            echo "PASS read-only $protected fallback preserves stale entry"
        fi
        chmod -R u+w "$protected_dir"
    done
    new_case readonly-completed
    mkdir -p "$cache_dir"
    touch "$cache_dir/$binary_name" "$cache_dir.complete"
    chmod -R a-w "${cache_dir%/*}"
    if [ -w "${cache_dir%/*}" ]; then
        echo "SKIP read-only completed cache permissions: requires an unprivileged user"
    else
        run_setup fallback
        assert_private fallback
        [ -f "$cache_dir.complete" ]
        [ ! -s "$cache_dir/$binary_name" ]
        echo "PASS read-only unusable completed entry falls back unchanged"
    fi
    chmod -R u+w "${cache_dir%/*}"
fi

[ ! -e "$test_dir/executed" ]
echo "Offline tool-cache assertions passed."
