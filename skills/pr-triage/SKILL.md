---
name: pr-triage
description: Triage a GitHub PR by reading all review comments, security findings, code-quality comments, and human feedback, then fixing or responding to each thread.
---

Use the shared MagmaMoose PR triage workflow.

Read and follow:
- `shared/pr-triage.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

Expected input:
- PR number, PR URL, branch name, or enough context to identify the pull request.

Expected behavior:
- Read all unresolved PR comments and review threads.
- Include GHAS, Copilot, code-quality bots, CI feedback, and human review comments.
- Decide whether each thread requires a code change, a reply, or no action.
- Make safe code changes where appropriate.
- Run relevant tests, linters, and type checks when available.
- Reply clearly to each addressed thread.
- Resolve threads only when the issue has genuinely been handled.
- Produce a final summary of what was changed, what was answered, and anything still requiring human attention.
