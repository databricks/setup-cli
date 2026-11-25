#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_REF:?Missing GITHUB_REF}"
: "${EVENT_NAME:?Missing EVENT_NAME}"
: "${AFTER:?Missing AFTER}"
: "${GH_REPO:?Missing GH_REPO}"

if [ "$GITHUB_REF" != refs/heads/main ]; then
    echo "Error: releases may only be published from main" >&2
    exit 1
fi

if ! [[ "$AFTER" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: invalid event commit" >&2
    exit 1
fi

if ! [[ "${GITHUB_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: missing or invalid GitHub run ID" >&2
    exit 1
fi

version_at() {
    local version
    version=$(git show "${1}:VERSION")
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: expected a stable numeric VERSION at $1" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

current_revision=$(git rev-list -1 --first-parent HEAD -- VERSION)
if ! [[ "$current_revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: main has no VERSION commit" >&2
    exit 1
fi
current_version=$(version_at "$current_revision")
revisions="$current_revision"
case "$EVENT_NAME" in
push)
    if ! [[ "${BEFORE:-}" =~ ^[0-9a-f]{40}$ ]]; then
        echo "Error: invalid push base" >&2
        exit 1
    fi
    if ! [[ "$BEFORE" =~ ^0+$ ]]; then
        if ! git merge-base --is-ancestor "$BEFORE" "$AFTER"; then
            echo "Error: push range is unavailable or not fast-forward" >&2
            exit 1
        fi
        revisions=$(git rev-list --reverse --first-parent "${BEFORE}..${AFTER}" -- VERSION)
        revisions="${revisions}"$'\n'"${current_revision}"
    fi
    ;;
workflow_dispatch)
    ;;
*)
    echo "Error: unsupported release event '$EVENT_NAME'" >&2
    exit 1
    ;;
esac

tag_records=$(git for-each-ref --format='%(refname)%09%(objecttype)%09%(*objecttype)%09%(*objectname)' refs/tags)
recovery_revisions=""
while IFS=$'\t' read -r reference object_type target_type target; do
    if [ "$object_type" != tag ]; then
        continue
    fi
    subject=$(git for-each-ref --format='%(contents:subject)' "$reference")
    if [[ "$subject" != "setup-cli-release:v1 run=${GITHUB_RUN_ID} "* ]]; then
        continue
    fi
    tag="${reference#refs/tags/}"
    if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        [ "$target_type" != commit ] ||
        ! [[ "$target" =~ ^[0-9a-f]{40}$ ]] ||
        [ "$subject" != "setup-cli-release:v1 run=${GITHUB_RUN_ID} tag=${tag} target=${target}" ]; then
        echo "Error: invalid release provenance for $reference" >&2
        exit 1
    fi
    if [ "v$(version_at "$target")" != "$tag" ] ||
        ! git merge-base --is-ancestor "$target" HEAD; then
        echo "Error: invalid release provenance target for $reference" >&2
        exit 1
    fi
    recovery_revisions="${recovery_revisions}${target}"$'\n'
done <<< "$tag_records"
revisions="${recovery_revisions}${revisions}"

if [ "$EVENT_NAME" = push ]; then
    history_revisions=$(git log --format=%H -- VERSION)
    selected_revisions=""
    event_revisions=$'\n'"${revisions}"$'\n'
    history_versions=" "
    while IFS= read -r revision; do
        if [ -z "$revision" ]; then
            continue
        fi
        version=$(version_at "$revision")
        if [[ "$history_versions" == *" $version "* ]]; then
            continue
        fi
        history_versions="${history_versions}${version} "
        if [[ "$event_revisions" == *$'\n'"$revision"$'\n'* ]] ||
            ! git show-ref --verify --quiet "refs/tags/v$version"; then
            selected_revisions="${revision}"$'\n'"${selected_revisions}"
        fi
    done <<< "$history_revisions"
    revisions="${selected_revisions}${revisions}"
fi

versions=()
version_revisions=()
seen_versions=" "
while IFS= read -r revision; do
    if [ -z "$revision" ]; then
        continue
    fi
    version=$(version_at "$revision")
    if [[ "$seen_versions" == *" $version "* ]]; then
        continue
    fi
    seen_versions="${seen_versions}${version} "
    versions+=("$version")
    version_revisions+=("$revision")
done <<< "$revisions"

for index in "${!versions[@]}"; do
    tag="v${versions[$index]}"
    release_exists=false
    if response=$(gh api --include --silent "repos/${GH_REPO}/releases/tags/${tag}"); then
        release_exists=true
    else
        status_line="${response%%$'\n'*}"
        case "$status_line" in
        HTTP/*" 404 "*)
            ;;
        *)
            echo "Error: release lookup failed for $tag; refusing to create it" >&2
            exit 1
            ;;
        esac
    fi

    if ! git show-ref --verify --quiet "refs/tags/$tag"; then
        git -c user.name='github-actions[bot]' \
            -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
            tag -a "$tag" "${version_revisions[$index]}" \
            -m "setup-cli-release:v1 run=${GITHUB_RUN_ID} tag=${tag} target=${version_revisions[$index]}"
    elif [ "$release_exists" = true ]; then
        continue
    fi
    git push origin "refs/tags/$tag"
    if [ "$release_exists" = false ]; then
        gh release create "$tag" --verify-tag --generate-notes --title "$tag" --latest=false
    fi
done

main_version=$(gh api --header 'Accept: application/vnd.github.raw+json' "repos/${GH_REPO}/contents/VERSION?ref=main")
if [ "$main_version" = "$current_version" ]; then
    gh release edit "v${current_version}" --latest
else
    echo "Main now uses $main_version; not marking v${current_version} as Latest"
fi
