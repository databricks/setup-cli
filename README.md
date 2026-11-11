# setup-cli

setup-cli makes it easy to install the [Databricks CLI](https://github.com/databricks/cli) in your environment.

It provides a composite GitHub Action and a portable installation script that can be used in most CI/CD systems and development environments.

Full documentation about installation can be found at:
* (AWS) https://docs.databricks.com/en/dev-tools/cli/install.html
* (Azure) https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/install
* (GCP) https://docs.gcp.databricks.com/en/dev-tools/cli/install.html

## Usage

This repository contains an `install.sh` script that can be invoked to install the Databricks CLI.

To install the latest version, run the following command:

```bash
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
```

To install a specific version, you can replace `main` with a specific release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/v1.26.0/install.sh | sh
```

## GitHub Actions

This repository can be used from GitHub Actions.

For a complete example of how to use the Databricks CLI in a GitHub Actions workflow, see the following guide:
* (AWS) https://docs.databricks.com/en/dev-tools/bundles/ci-cd.html
* (Azure) https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/ci-cd
* (GCP) https://docs.gcp.databricks.com/en/dev-tools/bundles/ci-cd.html

To always use the latest version of the Databricks CLI, use the action from the `main` branch:

```yml
- uses: databricks/setup-cli@main
```

In case you need to use a specific version of the Databricks CLI, use the action from a release tag:

```yml
- uses: databricks/setup-cli@v1.26.0
```

Replace the tag with the version you want to use.

Alternatively, you can specify the version as a parameter to the action:

```yml
- uses: databricks/setup-cli@main
  with:
    version: 1.26.0
```

### Runner tool cache

Release builds with an exact resolved `X.Y.Z` version reuse
`$RUNNER_TOOL_CACHE/databricks/<version>/<arch>`, with an adjacent
`<arch>.complete` marker, following the `@actions/tool-cache` layout.
Snapshots do not use this cache.

The runner tool cache must be trusted and isolated by operating system. Cached
executables are checked for usability without running them; the cache is not an
integrity boundary against writers with access to it. Downloads are checksum
verified before extraction.

Cache writers use a non-blocking per-key directory lock and private staging.
Contention, read-only or stale entries that cannot be replaced, and cache write
failures fall back to a private installation under `$RUNNER_TEMP`. Locks are never
waited on or automatically broken; an abandoned lock also causes fallback.

## Preview notice

Please note that the Databricks CLI is in public preview as defined on
https://docs.databricks.com/en/release-notes/release-types.html.
This means that it has medium-to-high maturity and can be used in production.

## Security

Release archives downloaded by the action and `install.sh` are verified against the SHA-256 checksums published with the CLI release before extraction. Snapshot builds do not use this release-manifest verification. Checksums detect corrupted downloads; they do not replace HTTPS certificate verification.

To pin the action's code, use a full commit SHA instead of a movable branch or tag:

```yml
- uses: databricks/setup-cli@<full-commit-sha> # vX.Y.Z
```

When using the installation script, select a release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/vX.Y.Z/install.sh | sh
```

Use a full commit SHA in place of the tag when the script itself must be immutable. A pinned action revision does not pin the CLI if you request a floating version selector.

## Troubleshooting

### TLS inspection and corporate proxies

On self-hosted Windows runners behind a TLS-inspecting corporate proxy, curl exit code 35 reports a TLS handshake failure; code 60 reports peer-certificate verification failure. Read the full error before changing trust settings: neither code alone proves that a corporate CA is missing.

First run `command -v curl` and `curl --version` in a `shell: bash` step under the runner's service account and environment. The first version line shows the active TLS backend; parenthesized backends are alternatives. Do not infer the backend from Git for Windows' bash alone.

Keep certificate and hostname verification and your organization's revocation policy intact. If revocation endpoints are blocked, ask your administrator to restore access; do not disable verification or revocation checks, or switch backends to bypass them.

#### Option 1: Windows trust store (Schannel)

Ask your administrator to provision the approved corporate root CA in the Windows trusted root store used by the runner's service account, not just an interactive user's store. Schannel uses Windows certificate trust.

If curl already uses Schannel, no backend selector is needed. Otherwise, use `CURL_SSL_BACKEND` only if `curl --version` reports `MultiSSL` and lists Schannel as an available backend. Set it at the job level and confirm Schannel is active, not parenthesized, in the diagnostic step:

```yaml
jobs:
  my-job:
    runs-on: [self-hosted, Windows, X64]
    env:
      CURL_SSL_BACKEND: schannel
    steps:
      - name: Check curl backend
        shell: bash
        run: |
          command -v curl
          curl --version
      - uses: databricks/setup-cli@main
```

#### Option 2: CA bundle for a file-based backend

For an organization-approved file-based backend such as OpenSSL, set this job-level environment instead:

```yaml
env:
  CURL_CA_BUNDLE: 'C:\certs\ca-bundle.pem'
```

Use an absolute path readable by the runner's service account to a maintained PEM bundle containing the approved corporate CA roots and public roots needed for downloads, including redirects. This replaces curl's default CA file rather than appending certificates.

`CURL_CA_BUNDLE` is ignored with Schannel. Remove any Schannel selector and confirm a non-Schannel file-based backend is active before using this option. A CA bundle configures trust, not revocation; have your administrator confirm that the backend meets your organization's revocation policy.

These examples configure curl. Wildcard version discovery uses Git, whose `http.sslBackend` and `http.sslCAInfo` settings may need separate configuration; snapshot downloads use `gh`, not curl. Configure each client for the runner's service account rather than assuming curl settings cover the whole job.

See curl's [certificate verification guide](https://curl.se/docs/sslcerts.html) and [manual](https://curl.se/docs/manpage.html), and Git's [TLS configuration](https://git-scm.com/docs/git-config).
