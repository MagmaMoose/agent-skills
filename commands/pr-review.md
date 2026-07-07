---
description: Review a pull request end to end (correctness, security, repo conventions, tests) and post ONE consolidated GitHub review with inline comments + a verdict
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(rm:*), Read, Grep, Glob, Write
---

Review a PR end to end using the shared MagmaMoose PR review workflow.

Read and follow:
- `shared/pr-review.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

PR input: $ARGUMENTS
