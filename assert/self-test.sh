#!/usr/bin/env bash

set -euo pipefail

assert_dir="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/workspace/setup-cli/nested" "$test_dir/mocks"
touch "$test_dir/workspace/setup-cli/nested/expected"

check_clean() {
    local name="$1" expected="$2" lookup_path="${3:-$PATH}" status=0
    (
        cd "$test_dir/workspace"
        PATH="$lookup_path" bash "$assert_dir/clean.sh"
    ) > "$test_dir/output" 2>&1 || status=$?
    if [ "$status" -ne "$expected" ]; then
        cat "$test_dir/output" >&2
        echo "$name: expected exit $expected, got $status" >&2
        exit 1
    fi
    echo "PASS $name"
}

check_clean 'checkout contents are allowed' 0
touch "$test_dir/workspace/unexpected.txt"
check_clean 'unrelated leaked file is rejected' 1
rm "$test_dir/workspace/unexpected.txt"
touch "$test_dir/workspace/setup-cli-leaked.zip"
check_clean 'checkout-prefix leaked file is rejected' 1
rm "$test_dir/workspace/setup-cli-leaked.zip"
cat > "$test_dir/mocks/find" <<'MOCK'
#!/usr/bin/env bash
exit 7
MOCK
chmod +x "$test_dir/mocks/find"
check_clean 'filesystem scan failure propagates' 7 "$test_dir/mocks:$PATH"
