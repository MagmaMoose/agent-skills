---
description: Read every PR comment (GHAS, Copilot, code-quality, human), fix the code, reply, and resolve each thread
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Read, Edit, Write, Grep, Glob
---

Triage a PR using the shared MagmaMoose PR triage workflow.

Read and follow:
- `shared/pr-triage.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

PR input: $ARGUMENTS
