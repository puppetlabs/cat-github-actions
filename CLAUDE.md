# Claude in This Repository

## How Claude Is Used

Claude runs automatically on every pull request via GitHub Actions. It does **not** need to be invoked manually — it triggers on its own whenever a PR is opened, updated, marked ready for review, or reopened.

Draft PRs are skipped. Claude will begin reviewing once a PR is marked ready for review.

## What Triggers a Review

The workflow fires on these PR events:

- `opened` — a new PR is created
- `synchronize` — new commits are pushed to an existing PR
- `ready_for_review` — a draft PR is promoted to ready
- `reopened` — a previously closed PR is reopened

## What Claude Does

Claude reviews the pull request and posts its feedback as a PR comment. Only one review runs at a time per PR — if a new commit is pushed while a review is in progress, the in-flight review is cancelled and a fresh one starts.

## Workflow Location

The GitHub Actions workflow is defined at:

```
.github/workflows/claude-pr.yml
```

## Required Secrets

The workflow requires the following secrets to be configured in the repository (or organization) settings:

| Secret                      | Purpose                                                                |
| --------------------------- | ---------------------------------------------------------------------- |
| `ANTHROPIC_CODE_REVIEW_KEY` | Anthropic API key used to authenticate Claude                          |
| `GITHUB_TOKEN`              | Automatically provided by GitHub Actions; used to post review comments |

## Permissions

Claude's workflow runs with the following GitHub permissions:

- `contents: read` — to check out and read the code
- `pull-requests: write` — to post review comments on the PR

## Notes for Contributors

- You do not need to do anything to trigger a review — it runs automatically.
- If you push additional commits, the previous review job will be cancelled and a new one will start.
- Claude's comments will appear in the PR alongside human reviewer comments.
- Claude's feedback is advisory. Merging decisions remain with human reviewers.
