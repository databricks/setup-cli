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

To use the CLI version bundled with the action's current `main` revision:

```yml
- uses: databricks/setup-cli@main
```

Without a `version` input, the action reads its bundled `VERSION` file; it does not query the latest upstream release. Pinning the action revision also pins this default.

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

You can also use a floating wildcard selector to resolve the latest matching version at installation time, independently of the bundled default:

```yml
- uses: databricks/setup-cli@main
  with:
    version: 1.*
```

The action supports `X.Y.*` to resolve to the latest patch release and `X.*` to resolve to the latest minor and patch release. This lets you stay on a compatible version line without manually updating to every release.

Wildcard versions are resolved from strict `vX.Y.Z` Git tags; tags with prerelease or other suffixes are ignored. GitHub release metadata is not queried. If a new tag appears before its release assets finish uploading, installation can temporarily fail with HTTP 404. Retry after the release finishes.

## Preview notice

Please note that the Databricks CLI is in public preview as defined on
https://docs.databricks.com/en/release-notes/release-types.html.
This means that it has medium-to-high maturity and can be used in production.
