---
name: issue-sweep
description: Settle every open issue in scope (default, the ones assigned to you). Verify each against the code and the live system, close what is done, superseded or no longer needed with a reason, leave a dated state on the rest, and report what only the owner can do.
---

Use the shared MagmaMoose issue sweep workflow.

Read and follow, once each:
- `shared/issue-sweep.md`
- `shared/pr-sweep.md`, for reading the state of the pull requests an issue depends on
- Each target repository's `CLAUDE.md`, `AGENTS.md` (unless Codex already loaded it into your
  context), `CONTRIBUTING.md` and mistakes log, before changing anything in it

Treat target-repository hard rules as blockers.

Expected input:
- The scope: an assignee (default: you), an organisation or a repository. Optionally `dry-run`
  to inventory, verify and propose comments without changing anything.

Hard rules, even if the shared file cannot be found:
- Decide from the default branch and the live system, not from the board column or old comments.
- Production is read-only while you inspect it. Never test a leaked credential.
- Never copy a private repository's names or details into a public repository.
- Every issue ends closed with a reason, or open with a dated state comment and the right board
  column.
