#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

version="$(cat "$repo_dir/VERSION")"
archive="databricks_cli_${version}_linux_amd64.zip"
manifest="databricks_cli_${version}_SHA256SUMS"
mkdir -p "$test_dir/fixture"
printf '#!/bin/sh\nprintf "Databricks CLI test fixture\\n"\n' > "$test_dir/fixture/databricks"
(cd "$test_dir/fixture" && zip -q "$archive" databricks)

if command -v sha256sum >/dev/null 2>&1; then
    hash_tool="$(command -v sha256sum)"
    hash_kind=sha256sum
    checksum_output="$("$hash_tool" "$test_dir/fixture/$archive")"
else
    hash_tool="$(command -v shasum)"
    hash_kind=shasum
    checksum_output="$("$hash_tool" -a 256 "$test_dir/fixture/$archive")"
fi
digest="${checksum_output%% *}"
unzip_tool="$(command -v unzip)"
shasum_tool="$(command -v shasum)"
sh_tool="$(command -v sh)"
bash_tool="$(command -v bash)"

for script in install.sh setup_release.sh; do
    for scenario in valid mismatch missing duplicate malformed trailing-fields hash-failure archive-failure manifest-failure no-tool shasum shasum-failure; do
        case_dir="$test_dir/$script-$scenario"
        mkdir -p "$case_dir/bin" "$case_dir/target" "$case_dir/tmp" "$case_dir/fixture"
        cp "$test_dir/fixture/$archive" "$case_dir/fixture/$archive"
        printf '%s  %s\n' "$digest" "$archive" > "$case_dir/fixture/$manifest"
        case "$scenario" in
            mismatch) printf 'corrupted' >> "$case_dir/fixture/$archive" ;;
            missing) printf '%s  unrelated.zip\n' "$digest" > "$case_dir/fixture/$manifest" ;;
            duplicate) printf '%s  %s\n' "$digest" "$archive" >> "$case_dir/fixture/$manifest" ;;
            malformed) printf 'invalid  %s\n' "$archive" > "$case_dir/fixture/$manifest" ;;
            trailing-fields) printf '%s  %s extra\n' "$digest" "$archive" > "$case_dir/fixture/$manifest" ;;
        esac
        for utility in awk cat chmod cp cut install mkdir mktemp rm; do
            ln -s "$(command -v "$utility")" "$case_dir/bin/$utility"
        done
        cat > "$case_dir/bin/uname" <<'MOCK'
#!/bin/sh
case "$1" in
    -s) echo Linux ;;
    -m) echo x86_64 ;;
    *) exit 1 ;;
esac
MOCK
        cat > "$case_dir/bin/curl" <<'MOCK'
#!/bin/sh
for argument do url=$argument; done
filename=${url##*/}
case "$CHECKSUM_TEST_SCENARIO:$filename" in
    archive-failure:*.zip|manifest-failure:*_SHA256SUMS) exit 22 ;;
esac
cp "$CHECKSUM_TEST_FIXTURE/$filename" "$filename"
MOCK
        cat > "$case_dir/bin/unzip" <<'MOCK'
#!/bin/sh
echo extraction >> "$CHECKSUM_TEST_EVENTS"
exec "$CHECKSUM_TEST_UNZIP" "$@"
MOCK
        cat > "$case_dir/hash-tool" <<'MOCK'
#!/bin/sh
echo "hash:${0##*/}" >> "$CHECKSUM_TEST_EVENTS"
if [ "${0##*/}" = shasum ]; then
    "$CHECKSUM_TEST_SHASUM" "$@" || exit $?
elif [ "$CHECKSUM_TEST_HASH_KIND" = shasum ]; then
    "$CHECKSUM_TEST_HASH" -a 256 "$@" || exit $?
else
    "$CHECKSUM_TEST_HASH" "$@" || exit $?
fi
case "$CHECKSUM_TEST_SCENARIO" in
    hash-failure|shasum-failure) exit 7 ;;
esac
MOCK
        chmod +x "$case_dir/hash-tool"
        case "$scenario" in
            no-tool) ;;
            shasum|shasum-failure) cp "$case_dir/hash-tool" "$case_dir/bin/shasum" ;;
            *) cp "$case_dir/hash-tool" "$case_dir/bin/sha256sum" ;;
        esac
        chmod +x "$case_dir/bin/uname" "$case_dir/bin/curl" "$case_dir/bin/unzip"
        : > "$case_dir/events"
        : > "$case_dir/github-path"
        if [ "$script" = install.sh ]; then
            sed "s|TARGET=\"/usr/local/bin\"|TARGET=\"\$CHECKSUM_TEST_TARGET\"|" "$repo_dir/$script" > "$case_dir/$script"
            shell_tool="$sh_tool"
            script_path="$case_dir/$script"
        else
            shell_tool="$bash_tool"
            script_path="$repo_dir/$script"
        fi
        status=0
        env -i PATH="$case_dir/bin" TMPDIR="$case_dir/tmp" \
            VERSION="$version" RUNNER_OS=Linux RUNNER_ARCH=X64 \
            RUNNER_TEMP="$case_dir/tmp" GITHUB_PATH="$case_dir/github-path" \
            CHECKSUM_TEST_TARGET="$case_dir/target" CHECKSUM_TEST_SCENARIO="$scenario" \
            CHECKSUM_TEST_FIXTURE="$case_dir/fixture" CHECKSUM_TEST_EVENTS="$case_dir/events" \
            CHECKSUM_TEST_HASH="$hash_tool" CHECKSUM_TEST_HASH_KIND="$hash_kind" \
            CHECKSUM_TEST_SHASUM="$shasum_tool" \
            CHECKSUM_TEST_UNZIP="$unzip_tool" \
            "$shell_tool" "$script_path" > "$case_dir/output" 2>&1 || status=$?
        case "$scenario" in
            valid|shasum)
                if [ "$status" -ne 0 ]; then
                    cat "$case_dir/output"
                    echo "$script/$scenario unexpectedly failed" >&2
                    exit 1
                fi
                grep -q '^extraction$' "$case_dir/events"
                if [ "$script" = install.sh ]; then
                    test -x "$case_dir/target/databricks"
                else
                    test -x "$(cat "$case_dir/github-path")/databricks"
                fi
                if [ "$scenario" = shasum ]; then
                    grep -q '^hash:shasum$' "$case_dir/events"
                fi
                ;;
            *)
                if [ "$status" -eq 0 ] || grep -q '^extraction$' "$case_dir/events" || [ -s "$case_dir/github-path" ] || [ -e "$case_dir/target/databricks" ]; then
                    cat "$case_dir/output"
                    echo "$script/$scenario did not fail before extraction" >&2
                    exit 1
                fi
                ;;
        esac
        echo "$script/$scenario passed"
    done
done
