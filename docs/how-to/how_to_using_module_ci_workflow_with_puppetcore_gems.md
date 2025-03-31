# How to use the module_ci workflow with puppetcore gems

## Description

This guide explains how to configure your repository to use the shared `module_ci.yml` workflow with PuppetCore Gems. The workflow is designed to maintain backward compatibility with existing consumers (like puppetlabs-apache and puppetlabs-ntp) while providing the capability to install and use gems from the private PuppetCore gem source.

## Prerequisites

- A GitHub repository that needs to use the `module_ci.yml` workflow
- Access to repository settings to configure secrets
- A valid `PUPPET_FORGE_TOKEN` with access to the private gem source

## Configuration Requirements

### Required Settings

To use PuppetCore Gems with the module_ci workflow, your repository must meet these requirements:

1. **Set up the PUPPET_FORGE_TOKEN secret**:
   - Navigate to your repository on GitHub
   - Go to Settings > Secrets and variables > Actions
   - Add a new repository secret named `PUPPET_FORGE_TOKEN` with your valid token value

2. **Configure Ruby Version**:
   - Must specify a Ruby version >= 3.1 (required for PuppetCore Gems)
   - The default Ruby version in module_ci.yml is 2.7 and must be overridden

### Optional Settings

- **PuppetCore API Type**:
  - By default, set to 'forge-key'
  - Can be changed to 'license-key' if required

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

## How It Works

When properly configured, the `module_ci.yml` workflow will:

1. Inherit the `PUPPET_FORGE_TOKEN` secret from the consumer repository.
2. Set the following `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM` environment variable ensuring authentication against the <https://rubygems-puppetcore.puppet.com> gemsource, e.g,:

   ```shell
   BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM: "forge-key:${{ secrets.PUPPET_FORGE_TOKEN }}"
   ```

3. Install gems from <https://rubygems-puppetcore.puppet.com>.

## Troubleshooting

Common issues and their solutions:

- **Bundle install fails**: Ensure Ruby version is set to at least 3.1
- **Authentication errors**: Verify the PUPPET_FORGE_TOKEN is correctly set and has appropriate permissions

## Appendix

### Sample Implementation

Example configuration in a consuming repository:

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
      ruby_version: '3.1'
      puppetcore_api_type: 'license-key'
    secrets: "inherit"
```

### Security Considerations

- Never hardcode the PUPPET_FORGE_TOKEN in your workflow files
- Use the `secrets: "inherit"` pattern to securely pass tokens
- Regularly rotate your tokens following security best practices
