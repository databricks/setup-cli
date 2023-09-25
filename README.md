# setup-cli

This is a composite GitHub Action that sets up the Databricks CLI (preview version `>=0.100`) in your GitHub Actions workflow.

## Usage

In your GitHub Actions workflow, use the following step:

```yml
- uses: databricks/setup-cli
```

<!--
### Snapshot build

Ensure you have a token with access to the [Databricks CLI repository](https://github.com/databricks/cli).

In your GitHub Actions workflow, use the following step:

```yml
- uses: databricks/setup-cli
  with:
    token: ${{ secrets.GH_TOKEN }}
```
//-->

## Preview notice

Please note that the Databricks CLI and Databricks asset bundles are in public preview
as defined on https://docs.databricks.com/en/release-notes/release-types.html. This means
that it has medium-to-high maturity and can be used in production.
