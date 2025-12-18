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
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/v0.281.0/install.sh | sh
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
- uses: databricks/setup-cli@v0.281.0
```

Replace the tag with the version you want to use.

Alternatively, you can specify the version as a parameter to the action:

```yml
- uses: databricks/setup-cli@main
  with:
    version: 0.281.0
```

## Preview notice

Please note that the Databricks CLI is in public preview as defined on
https://docs.databricks.com/en/release-notes/release-types.html.
This means that it has medium-to-high maturity and can be used in production.
