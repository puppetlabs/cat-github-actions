# How to enable safe fork-PR CI against private puppetcore

## Description

This guide explains how to enable acceptance testing against the private Puppet Forge (puppetcore) for pull requests from forks, while keeping `PUPPET_FORGE_TOKEN` and other secrets safe from exfiltration by untrusted contributors.

The setup splits CI into two independent tracks:

- **Spec track** — runs on the standard `pull_request` event. No secrets in scope. Runs on every PR, including from forks, with no gating.
- **Acceptance track** — runs on `pull_request_target` with secrets in scope. For same-repo PRs, runs automatically. For fork PRs, runs only when a CODEOWNER applies the `allowed-for-ci` label after reviewing the PR's contents.

## Threat model

Acceptance tests run `bundle exec rake litmus:*`, which executes arbitrary Ruby and shell scripts from the PR's working tree (Rakefile, spec helpers, fixtures). Under `pull_request_target` these scripts run in the base-repo's privileged context with secrets available — code execution from PR-controlled code is the *design*, so we cannot eliminate it. Every control below exists to ensure that execution only happens with explicit, fresh, human consent.

A malicious fork PR could (a) modify `Rakefile`, `spec/**`, `metadata.json`, `Gemfile`, `.fixtures.yml` to exfiltrate environment variables, (b) attempt shell injection through interpolated workflow inputs, (c) push to the fork after a CODEOWNER labels the PR, hoping the label sticks. The controls below close (a) via human review before label, (b) via env-var passthrough in the reusable workflows, and (c) via automatic label removal on each new commit.

## Prerequisites

- A puppetlabs module repository.
- Repo admin access to configure labels, rulesets, environments, and secrets.
- Existing `PUPPET_FORGE_TOKEN` (and, where applicable, `TWINGATE_PUBLIC_REPO_KEY`) secrets.

## Configuration steps

Complete **all** of these before flipping the caller workflow to the new pattern. Each step is independent; verify each before moving on.

### 1. Create the `allowed-for-ci` label

In the module repo: **Issues → Labels → New label**. Name it exactly `allowed-for-ci`. Description: "CODEOWNER review complete; run acceptance against private puppetcore for this commit."

### 2. Restrict who can apply the label (ruleset)

**Settings → Rules → Rulesets → New ruleset → Repository**. Add a rule targeting the `allowed-for-ci` label that restricts add/remove permissions to teams `@puppetlabs/devx` and `@puppetlabs/modules`. This is the security primitive that makes label-presence a meaningful trust signal.

If your repo's GitHub plan does not yet support label-scope rulesets, fall back to the environment approval gate (step 3) as the primary control and revisit once the feature is available.

### 3. Create the `puppetcore-fork` environment

**Settings → Environments → New environment** named `puppetcore-fork`. Configure:

- **Required reviewers**: `@puppetlabs/modules` (and/or `@puppetlabs/devx`).
- **Environment secrets**: copy `PUPPET_FORGE_TOKEN` and `TWINGATE_PUBLIC_REPO_KEY` into the environment. During pilot, keep them at repo level too so same-repo PRs continue to work without the environment gate.

The acceptance job uses the environment only on fork PRs (see `module_acceptance.yml` for the conditional), so non-fork PRs do not pause for approval.

### 4. Protect the `main` branch

**Settings → Rules → Rulesets**: require PRs to `main`, ≥1 CODEOWNER review, block force-push. Add a path filter requiring `@puppetlabs/devx` review for any change touching `.github/workflows/**`, `.github/actions/**`, or `CODEOWNERS`. `pull_request_target` always loads the workflow YAML from `main`, so protecting `main` is what makes the gate trustworthy.

### 5. Update the caller workflows

Replace `.github/workflows/ci.yml` with the two-track pattern (see [example/module/ci.yml](../../example/module/ci.yml)). Add a new file `.github/workflows/fork_ci_label_guard.yml` that strips the label on each new commit (see [example/module/fork_ci_label_guard.yml](../../example/module/fork_ci_label_guard.yml)).

Keep "Require approval for first-time contributors" enabled at the org Actions setting — it's an additional pre-execution gate independent of this design.

## Reviewer checklist (before applying the label)

Before a CODEOWNER applies `allowed-for-ci` to a fork PR, they **must** read the diff for these files. A change to any of them is grounds to refuse the label until the change is understood and acceptable:

- `.github/**` — any workflow change (cannot affect this run, but can land if merged).
- `Rakefile` — runs during acceptance.
- `spec/**` — spec helpers and fixtures execute during tests.
- `Gemfile`, `Gemfile.lock`, `metadata.json` — control which code is loaded.
- `.fixtures.yml` — controls test fixture sources.
- Any file under `tasks/`, `plans/`, `functions/`, or anywhere else that is loaded or executed as part of `litmus:provision`, `litmus:install_module`, or `litmus:acceptance:parallel`.

The Spec track has already run by the time the reviewer sees the PR; review its result alongside the diff.

## How it works

- A fork contributor opens a PR. `Spec` runs immediately (public track, no secrets). `Acceptance` does not run.
- A CODEOWNER reviews the diff, focusing on the files above, and applies `allowed-for-ci`. The `labeled` event triggers `Acceptance` on `pull_request_target`. The acceptance job targets the `puppetcore-fork` environment and pauses for environment approval. A `@puppetlabs/modules` member approves; acceptance runs with `PUPPET_FORGE_TOKEN` in scope.
- If the contributor pushes a new commit, `fork_ci_label_guard.yml` fires on `synchronize` and removes the label. The main caller workflow does **not** include `synchronize` in its `pull_request_target` trigger, so no acceptance run is created for the new commit. To run acceptance against the new code, a CODEOWNER must review again and re-apply the label.

## Verification

End-to-end test on the pilot module before declaring done:

1. Open a fork PR. Confirm `Spec` runs and `Acceptance` does not.
2. Apply `allowed-for-ci` as a CODEOWNER. Confirm `Acceptance` is queued and waits for environment approval.
3. Approve the environment run. Confirm acceptance runs against private puppetcore.
4. Push a new commit to the fork branch. Confirm: the label is removed automatically; `Spec` re-runs on the new commit; `Acceptance` does **not** auto-run.
5. As a non-CODEOWNER test account, attempt to add `allowed-for-ci`. Confirm the ruleset blocks it.
6. Open a fork PR that modifies `.github/workflows/ci.yml` (e.g., removes the gate). Confirm that on `pull_request_target` the **base** workflow definition runs, so the gate still holds.

## Troubleshooting

- **Acceptance never runs on a labeled fork PR**: check that `pull_request_target` is in the trigger list and that `types:` includes `labeled`. Confirm the label name is exactly `allowed-for-ci`.
- **Acceptance pauses indefinitely**: an environment reviewer has not approved. Check **Actions → workflow run → Review deployments**.
- **Label cannot be applied**: the ruleset is rejecting it. Confirm the user is in `@puppetlabs/devx` or `@puppetlabs/modules`.
- **Secrets missing inside acceptance**: confirm both repo-level (for same-repo PRs) and `puppetcore-fork` environment secrets are populated during pilot.

## Security considerations

- Do **not** add `synchronize` to the `pull_request_target` types in the caller's main `ci.yml`. Doing so re-races the label-strip workflow and can allow a malicious commit to inherit a prior label's authorization.
- Do **not** pass `secrets: inherit` to the `Spec` track. It runs on `pull_request` (untrusted) and must have no secrets in scope.
- Do **not** widen the trigger from `pull_request_target` to include user-controlled refs other than the PR head SHA pinned by the reusable workflow.
- The label name `allowed-for-ci` is a contract; changing it requires updating the reusable workflow's `if:` expressions and the label-guard's input.
