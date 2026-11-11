#!/bin/sh

set -eu

script_dir="$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)"
installer="${INSTALLER_SCRIPT:-$script_dir/../install.sh}"
installer_shell="${INSTALLER_SHELL:-sh}"
start_directory="$(pwd -P)"
test_root="$(mktemp -d)"
test_root="$(CDPATH='' cd -P "$test_root" && pwd -P)"
TEST_REAL_MKDIR="$(command -v mkdir)"
TEST_REAL_CP="$(command -v cp)"
TEST_ROOT="$test_root"
native_windows=0
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) native_windows=1 ;;
esac
export TEST_REAL_MKDIR TEST_REAL_CP TEST_ROOT

cleanup() {
    cd "$start_directory"
    chmod -R u+w "$test_root" 2>/dev/null || true
    rm -rf "$test_root"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

mkdir -p "$test_root/mock-bin"
cat > "$test_root/mock-bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
-s) printf '%s\n' "$TEST_OS" ;;
-m) printf '%s\n' x86_64 ;;
*) exit 1 ;;
esac
EOF
cat > "$test_root/mock-bin/mkdir" <<'EOF'
#!/bin/sh
printf '%s\n' mkdir >> "$TEST_LOG"
exec "$TEST_REAL_MKDIR" "$@"
EOF
cat > "$test_root/mock-bin/curl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' curl >> "$TEST_LOG"
for url do :; done
filename="${url##*/}"
case "$filename" in
*.zip)
    printf '%s\n' "$filename" > "$TEST_ARCHIVE"
    : > "$filename"
    ;;
*_SHA256SUMS)
    printf '%s  %s\n' \
        0000000000000000000000000000000000000000000000000000000000000000 \
        "$(cat "$TEST_ARCHIVE")" > "$filename"
    ;;
*) exit 1 ;;
esac
EOF
cat > "$test_root/mock-bin/unzip" <<'EOF'
#!/bin/sh
printf '%s\n' unzip >> "$TEST_LOG"
cat > databricks <<'BINARY'
#!/bin/sh
printf '%s\n' binary >> "$TEST_LOG"
printf '%s\n' 'Databricks CLI offline fixture'
BINARY
EOF
cat > "$test_root/mock-bin/cp" <<'EOF'
#!/bin/sh
for destination do :; done
case "$destination" in
"$TEST_ROOT"/*) ;;
*) exit 1 ;;
esac
printf '%s\n' cp >> "$TEST_LOG"
exec "$TEST_REAL_CP" "$@"
EOF
cat > "$test_root/mock-bin/sha256sum" <<'EOF'
#!/bin/sh
for filename do :; done
printf '%s  %s\n' \
    0000000000000000000000000000000000000000000000000000000000000000 \
    "$filename"
EOF
cp "$test_root/mock-bin/sha256sum" "$test_root/mock-bin/shasum"
chmod +x "$test_root/mock-bin/"*
PATH="$test_root/mock-bin:$PATH"
export PATH

fail() {
    printf '%s: %s\n' "$case_name" "$*" >&2
    exit 1
}

new_case() {
    case_name="$1"
    case_root="$test_root/$case_name"
    "$TEST_REAL_MKDIR" -p "$case_root/home with spaces" "$case_root/work" "$case_root/tmp"
    cd "$case_root/work"
    HOME="$case_root/home with spaces"
    TMPDIR="$case_root/tmp"
    TEST_LOG="$case_root/operations"
    TEST_ARCHIVE="$case_root/archive"
    TEST_OS=Linux
    export HOME TMPDIR TEST_LOG TEST_ARCHIVE TEST_OS
    unset TARGET DATABRICKS_CLI_INSTALL_DIR DATABRICKS_RUNTIME_VERSION CDPATH
    : > "$TEST_LOG"
}

expect_success() {
    if ! "$installer_shell" -s -- "$@" < "$installer" > "$case_root/output" 2>&1; then
        cat "$case_root/output" >&2
        fail "installation failed"
    fi
}

expect_failure() {
    if "$installer_shell" -s -- "$@" < "$installer" > "$case_root/output" 2>&1; then
        cat "$case_root/output" >&2
        fail "installation unexpectedly succeeded"
    fi
}

assert_installed() {
    [ -f "$1/databricks" ] || fail "missing executable at $1/databricks"
    [ "$("$1/databricks" -v)" = "Databricks CLI offline fixture" ] || fail "wrong executable"
}

assert_no_download() {
    if grep -q '^curl$' "$TEST_LOG"; then fail "download attempted for invalid target"; fi
}

new_case positional-precedence
export DATABRICKS_CLI_INSTALL_DIR="$case_root/unused-env" DATABRICKS_RUNTIME_VERSION=test TARGET="$case_root/unused-target"
expect_success "$case_root/argument with spaces/nested/bin"
assert_installed "$case_root/argument with spaces/nested/bin"
[ ! -e "$DATABRICKS_CLI_INSTALL_DIR" ] || fail "environment target used"
[ ! -e "$HOME/bin" ] || fail "DBR default used"
[ ! -e "$TARGET" ] || fail "generic TARGET used"

new_case environment-precedence
export DATABRICKS_CLI_INSTALL_DIR="$case_root/environment with spaces/nested/bin" DATABRICKS_RUNTIME_VERSION=test TARGET="$case_root/unused-target"
expect_success
assert_installed "$DATABRICKS_CLI_INSTALL_DIR"
[ ! -e "$HOME/bin" ] || fail "DBR default used"
[ ! -e "$TARGET" ] || fail "generic TARGET used"

new_case dbr-default
export DATABRICKS_CLI_INSTALL_DIR='' DATABRICKS_RUNTIME_VERSION=test TARGET="$case_root/unused-target"
expect_success
assert_installed "$HOME/bin"
[ ! -e "$TARGET" ] || fail "generic TARGET used"

for relative_target in 'nested/bin with spaces' '-bin with spaces'; do
    new_case "relative-$relative_target"
    expect_success "$relative_target"
    assert_installed "$case_root/work/$relative_target"
done

if [ "$native_windows" = 0 ]; then
    for relative_target in 'C:tools' 'a\tools' 'C:/tools' '\\server\share'; do
        new_case "relative-$relative_target"
        expect_success "$relative_target"
        assert_installed "$case_root/work/$relative_target"
    done
fi

new_case tilde-argument
expect_success '~'
assert_installed "$HOME"

new_case tilde-environment
tilde_prefix='~'
export DATABRICKS_CLI_INSTALL_DIR="$tilde_prefix/.local/bin with spaces"
expect_success
assert_installed "$HOME/.local/bin with spaces"

new_case cdpath
"$TEST_REAL_MKDIR" -p "$case_root/search/bin" "$case_root/work/bin"
export CDPATH="$case_root/search"
expect_success bin
assert_installed "$case_root/work/bin"
[ ! -e "$case_root/search/bin/databricks" ] || fail "CDPATH redirected installation"

new_case symlink
"$TEST_REAL_MKDIR" -p "$case_root/destination"
if ln -s "$case_root/destination" "$case_root/alias" 2>/dev/null && [ -L "$case_root/alias" ]; then
    expect_success "$case_root/alias"
    assert_installed "$case_root/destination"
else
    printf 'Skipped symlink: filesystem/user does not support symbolic links.\n'
fi

for argument_case in empty extra; do
    new_case "arguments-$argument_case"
    export DATABRICKS_CLI_INSTALL_DIR="$case_root/unused-env"
    if [ "$argument_case" = empty ]; then
        expect_failure ''
    else
        expect_failure "$case_root/unused-argument" extra
    fi
    grep -q 'Usage:' "$case_root/output" || fail "missing usage error"
    [ ! -s "$TEST_LOG" ] || fail "invalid arguments caused side effects"
    [ ! -e "$DATABRICKS_CLI_INSTALL_DIR" ] || fail "environment target created"
    [ ! -e "$case_root/unused-argument" ] || fail "argument target created"
    [ ! -e "$case_root/work/databricks" ] || fail "working directory used"
done

new_case file-target
printf '%s\n' sentinel > "$case_root/file"
expect_failure "$case_root/file"
grep -q 'not a directory' "$case_root/output" || fail "missing directory error"
[ "$(cat "$case_root/file")" = sentinel ] || fail "target file changed"
assert_no_download

new_case existing-installation
"$TEST_REAL_MKDIR" -p "$case_root/bin"
printf '%s\n' sentinel > "$case_root/bin/databricks"
expect_failure "$case_root/bin"
grep -q 'already exists' "$case_root/output" || fail "missing overwrite error"
[ "$(cat "$case_root/bin/databricks")" = sentinel ] || fail "existing installation changed"
assert_no_download

for permission_case in target parent; do
    new_case "permissions-$permission_case"
    "$TEST_REAL_MKDIR" -p "$case_root/readonly"
    chmod a-w "$case_root/readonly"
    if [ ! -w "$case_root/readonly" ]; then
        if [ "$permission_case" = target ]; then
            expect_failure "$case_root/readonly"
        else
            expect_failure "$case_root/readonly/nested/bin"
        fi
        grep -q 'not writable' "$case_root/output" || fail "missing permission error"
        assert_no_download
    else
        printf 'Skipped %s: filesystem/user does not enforce mode bits.\n' "$case_name"
    fi
done

if [ "$native_windows" = 1 ] && command -v cygpath >/dev/null 2>&1; then
    for path_format in m w; do
        new_case "windows-drive-$path_format"
        TEST_OS=MINGW64_NT
        export TEST_OS
        native_target="$(cygpath "-$path_format" "$case_root/native path/bin")"
        expect_success "$native_target"
        assert_installed "$case_root/native path/bin"
    done
fi

printf 'Offline install-target assertions passed (%s).\n' "$installer_shell"
