---
name: init-repo
description: Bootstrap Claude Code integration into a repository. Sets up CLAUDE.md, .claude/settings.json, and a GitHub Actions workflow so that @claude automatically reviews PRs using the ANTHROPIC_CODE_REVIEW_KEY secret. Use when onboarding a new repo to Claude Code.
allowed-tools: Read, Write, Bash, Glob
---

Bootstrap Claude Code integration into the current repository.

## Steps

1. **Confirm this is a git repo**
   Run `git rev-parse --show-toplevel`. If it fails, stop and tell the user.

2. **Detect the tech stack**
   Check for these files in the repo root:
   - `package.json` → Node/JS/TS
   - `Gemfile` → Ruby
   - `go.mod` → Go
   - `pyproject.toml` or `requirements.txt` → Python
   - `Cargo.toml` → Rust
   - `pom.xml` or `build.gradle` → Java

3. **Create CLAUDE.md**
   If one doesn't exist, create it with this content:

   ```
   # [repo name]

   [One-line description]

   ## Build & Test

   [Fill in based on detected stack — e.g. npm test, bundle exec rspec]

   ## Key Conventions

   [Leave blank for the user to fill in]
   ```

   If one already exists, leave it untouched and note it was skipped.

4. **Create .claude/settings.json**
   If one doesn't exist, run `mkdir -p .claude` to ensure the directory exists, then write `.claude/settings.json` based on the detected stack:
   - Node: allow `Bash(npm:*)`, `Bash(npx:*)`
   - Ruby: allow `Bash(bundle:*)`, `Bash(rake:*)`, `Bash(rspec:*)`
   - Python: allow `Bash(python:*)`, `Bash(pytest:*)`, `Bash(pip:*)`
   - Go: allow `Bash(go:*)`
   - Default (unknown stack): write an empty `allowedTools` array
     If one already exists, leave it untouched and note it was skipped.

5. **Create the GitHub Actions workflow**
   - If `.github/workflows/claude-pr.yml` already exists, leave it untouched and note it was skipped.
   - If it doesn't exist, run `mkdir -p .github/workflows/` if needed, then read `${CLAUDE_PLUGIN_ROOT}/claude-pr.yml` and write its contents to `.github/workflows/claude-pr.yml`.
   - If `${CLAUDE_PLUGIN_ROOT}/claude-pr.yml` cannot be read, stop and tell the user.

6. **Print a summary** of what was created and what was already in place. Include:
   - Which files were created vs skipped (already existed)
   - Always append a reminder that ANTHROPIC_CODE_REVIEW_KEY must exist in this repo's GitHub secrets, and that if it doesn't, the user should add it via: GitHub repo → Settings → Secrets
     and variables → Actions → New repository secret
   - Note that once the workflow is in place, every non-draft pull request will automatically receive a Claude code review when opened or updated
