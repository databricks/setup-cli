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

If you are planning to use this tool, please note that:

* The product is in preview and not intended to be used in production;
* The product may change or may never be released;
* While we will not charge separately for this product right now, we may charge for it in the future. You will still incur charges for DBUs.
* There's no formal support or SLAs for the preview - so please reach out to your account or other contact with any questions or feedback; and
* We may terminate the preview or your access at any time;
* Non-public information about the preview (including the fact that there is a preview for the feature/product itself) is confidential;

Also - should we decide to release it, we'd love for you to be a reference if you find it useful - please let us know if you'd be willing to do so. You can contact us at dabs-preview@databricks.com.

