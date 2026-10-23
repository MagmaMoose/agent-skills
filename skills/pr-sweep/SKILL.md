---
name: pr-sweep
description: Clear every open pull request in a GitHub org. Inventory them, fix the shared causes first, then merge, close or finish each one, settle the issues that keep re-creating PRs, and report what only the owner can do.
---

Use the shared MagmaMoose PR sweep workflow.

Read and follow, once each:
- `shared/pr-sweep.md`
- `shared/pr-triage.md`, for each PR's review threads and failing gates
- Each target repository's `CLAUDE.md`, `AGENTS.md` (unless Codex already loaded it into your
  context), `CONTRIBUTING.md` and mistakes log, before changing anything in it

Treat target-repository hard rules as blockers.

Expected input:
- The organisation name. Optionally a repository filter, and `dry-run` to inventory and plan
  without changing anything.

Hard rules, even if the shared file cannot be found:
- Never bypass branch protection or rulesets, and never edit repository, organisation or secret
  settings. Merge only what GitHub allows.
- Never copy a private repository's names or details into a public repository.
- Never enable auto-merge on a PR that applies infrastructure on merge; read its plan first.
- Every PR ends merged or closed with a reason, unless it is blocked on the owner; then say
  exactly what the owner must do.
