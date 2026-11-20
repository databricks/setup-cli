# Release publication

`tag.yml` publishes only from `main`, with job-scoped `contents: write`.
Its publish step passes the event name, push base, and event SHA through
environment variables to `publish-release.sh`. Checkout uses fresh `main`;
push-range candidates remain anchored to the original event SHAs.

Pushes preserve the original discovery of missing tags throughout fresh
`main`'s `VERSION` history. Newly discovered missing tags, first-parent
`before..after` retry candidates, same-run recovery tags, and the current
version are deduplicated and processed oldest first. When a version appears
more than once, a missing tag points to its newest version-changing commit,
as in the original tagger. This recovers untagged versions from replaced
pending runs, including versions outside the executing event's range.
Initial branch creation has no retry range but still discovers missing tags.
Manual dispatch processes only fresh `main`'s current version and its own
same-run recovery tags; it does not scan for missing historical tags.

The history scan does not nominate already-tagged historical versions for
release creation. They are considered only if they belong to the event's
retry range, are current, or carry this run's validated provenance.
This is the no-backfill boundary: newly tagged historical versions get
releases; unrelated pre-existing tags and other runs' provenance do not
become additional recovery candidates. A missing or non-fast-forward push
base fails closed. Only stable numeric versions are supported, and tags
point to version-changing commits rather than later unrelated commits.

## Retry provenance

A push-range/current-version retry list alone loses catch-up candidates once
their tag push succeeds: they then look like unrelated historical tags.
Run-scoped annotations retain precisely that ownership, without adopting all
missing historical releases, rewriting existing tags, or adding a state store.

Every new tag is annotated with this single-line subject:

```text
setup-cli-release:v1 run=<GITHUB_RUN_ID> tag=v<X.Y.Z> target=<commit SHA>
```

`GITHUB_RUN_ID` must be a positive decimal ID without leading zeroes. GitHub
keeps it stable across attempts; the attempt number is deliberately absent.
On a fresh checkout, the publisher reads local tag metadata and recovers only
annotations claiming that exact run. The tag must directly target a commit
reachable from fresh main; its strict versioned ref, annotation fields,
target SHA, and target's VERSION must agree. Malformed same-run provenance
fails closed. Unrelated annotations and lightweight tags are not provenance.
The marker is retry ownership metadata, not a new authorization or signature
verification mechanism; repository write permissions and the main-only gate
remain the authorization boundary.

New annotations use a command-local GitHub Actions bot identity. Existing
tags are never rewritten or converted to annotations. Configured Git signing
policy is preserved: `tag.gpgSign`, the signing key, and signer are not
overridden, and a required signer failure stops publication.

Rerun the **failed workflow run** after a tag push, partial publication, or
lost response. Its annotated catch-up tags remain recoverable even outside
its event range and without access to an older VERSION workflow run. A new
manual dispatch has a different run ID and intentionally does not adopt a
previous run's historical tags. The tag annotation is the only durable
provenance: there is no separate state store, mutable checkpoint, or new
runtime dependency. Losing or rewriting tags can lose that provenance.

Existing releases are not recreated; missing tags are restored even when
their releases exist. Only confirmed HTTP 404 lookups allow release creation.
Other API or transport errors fail the run with diagnostics.

## Latest and validation

Every release is created with `--latest=false`. After the batch succeeds,
the checkout's current version is explicitly marked Latest only if it still
matches `main`'s live `VERSION`. This also repairs a failed Latest update
and prevents an old event rerun from downgrading a newer version. The main
read and Latest update are not atomic with branch updates; the publication
group serializes workflow publishers, and later runs reconcile subsequent
pushes. No automatic historical Latest ordering is assumed.

The global concurrency group does not guarantee FIFO and may replace a
pending run. Every executing run includes fresh `main`'s version, even for
an older push or manual rerun. Pushes also discover intervening untagged
versions without an external retry-state dependency. Publication outside
this workflow is not serialized by its concurrency group.

Run `python3 .github/scripts/test_publish_release.py` for offline tests of
the script invoked by the workflow. Recovery tests model a fresh checkout
from pushed annotations, never an unavailable older workflow. Most tests
mock Git/GitHub commands; an annotation/signing test replays the actual tag
command in disposable bare repositories using existing local commit
objects. Tests create no commits, inherit no tokens, and use no network.

The protected runner configuration is unchanged. Migrating it still
depends on the separate runner configuration work in PR #273.
