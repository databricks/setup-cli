# setup-bricks

This is a composite GitHub Action that sets up the Bricks CLI in your GitHub Actions workflow.

As of March 2023, it installs the most recent snapshot build.

## Usage

Ensure you have a token with access to the [Bricks repository](https://github.com/databricks/bricks).

In your GitHub Actions workflow, use the following step:

```yml
- uses: databricks/setup-bricks@test
  with:
    token: ${{ secrets.GH_TOKEN }}
```
