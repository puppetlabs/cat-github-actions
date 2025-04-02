# How to inject puppetcore authentication into the shared workflows

## Description

This guide explains how to configure your repository to consume the following shared workflows and ensure that puppetcore dependencies are successfully bundle installed:

- `module_ci.yml`
- `gem_ci.yml`
- `tooling_mend_ruby.yml`

The above workflows are backward compatible and designed to work with both puppetcore and non-puppetcore repositories.

## Prerequisites

- A puppetcore repository that needs to use a shared workflow.
- Access to repository settings to configure secrets
- A valid `PUPPET_FORGE_TOKEN` with access to the private puppetcore gem source

## Configuration Requirements

### Required Settings

To use PuppetCore Gems with the above shared workflows, your repository must meet these requirements:

1. **Set up the PUPPET_FORGE_TOKEN secret**:
   - Navigate to your repository on GitHub
   - Go to Settings > Secrets and variables > Actions
   - Add a new repository secret named `PUPPET_FORGE_TOKEN` with your valid token value

2. **Configure Ruby Version to be >= 3.1**:
   - Ruby version >= 3.1 is required for PuppetCore Gems.
   - Some shared worklows, like `module_ci.yml`, have an old  default Ruby version that must be overridden

## Usage

Create or update your workflow file (typically `.github/workflows/ci.yml`) to look something like:

```yaml
name: "ci"

on:
  pull_request:
    branches:
      - "main"
  workflow_dispatch:

jobs:
  Spec:
    uses: "puppetlabs/cat-github-actions/.github/workflows/module_ci.yml@main"
    with:
      run_shellcheck: true
      ruby_version: '3.1' # Required for PuppetCore Gems
    secrets: "inherit" # Required to pass PUPPET_FORGE_TOKEN
```

For 2 example consumers, see:

* [puppet-upgrade ci.yml](https://github.com/puppetlabs/puppet-upgrade/blob/main/.github/workflows/ci.yml)
* [provision ci.yml](https://github.com/puppetlabs/provision/blob/main/.github/workflows/ci.yml)

## How It Works

The above shared workflows are designed to install gems from <https://rubygems-puppetcore.puppet.com>.  They

- **Inherit** the `PUPPET_FORGE_TOKEN` secret from the consumer repository and then **set** an environment variable of the same name.  This environment variable is required by some repositories to "switch" between either the public or puppetcore gems.
- **Set** the `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM` environment variable ensuring authentication against the <https://rubygems-puppetcore.puppet.com> gemsource.  For example,

```bash
BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM: "forge-key:${{ secrets.PUPPET_FORGE_TOKEN }}"
```

## Troubleshooting

Common issues and their solutions:

- **Bundle install fails**: Ensure Ruby version is set to at least 3.1
- **Authentication errors**: Verify the PUPPET_FORGE_TOKEN is correctly set and has appropriate permissions

## Appendix

### Security Considerations

- Use the `secrets: "inherit"` pattern to securely pass tokens from your consumer to shared workflow.
- Push secrets into environment variables for use by code.  This is another github pattern that maintains redaction of secrets in logs
