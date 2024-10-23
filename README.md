# cat-github-actions

This repository contains GitHub Actions workflows and configurations for automating various tasks related to the `Content and Tooling (CAT)` project. These workflows help ensure code quality, automate testing, and streamline the release process.

## Workflows

The following are the workflows we currently maintain in this repository:
* gem_acceptance: runs automated acceptance CI on tooling PRs
* gem_ci: runs automated unit testing CI on tooling PRs
* gem_release_prep: prepares the gem for release by running necessary pre-release checks and tasks
* gem_release: handles the release process of the gem, including versioning and publishing
* lint: runs linting checks on the codebase to ensure code quality and consistency
* mend_ruby: automates the usage of mend for vulnerability scanning on modules
* module_acceptance: runs automated acceptance CI for modules on PRs
* module_ci: runs automated unit testing CI for modules on PRs
* module_release_prep: prepares the module for release by running necessary pre-release checks and tasks
* module_release: handles the release process of the module, including versioning and publishing
* tooling_mend_ruby: automates the usage of mend for vulnerability scanning on tools
* workflow-restarter-test: tests the workflow restarter functionality
* workflow-restarter: restarts workflows that have failed or need to be re-run
