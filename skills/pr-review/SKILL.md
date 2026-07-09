---
name: pr-review
description: Review a GitHub PR end to end for correctness, security, repository conventions, tests, and produce one consolidated review.
---

Use the shared MagmaMoose PR review workflow.

Read and follow:
- `shared/pr-review.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

Expected input:
- PR number, PR URL, branch name, or enough context to identify the pull request.

Expected behavior:
- Inspect the PR diff and relevant surrounding code.
- Check correctness, security, repository conventions, tests, and maintainability.
- Prefer actionable comments over vague feedback.
- Avoid duplicate comments.
- Produce one consolidated review summary.
- Include a clear verdict, following the shared policy: approve when it isn't your own PR and there are zero blocking and zero should-fix findings; request changes on any blocking finding; comment otherwise (and always comment on your own PR, since GitHub forbids approving it).
