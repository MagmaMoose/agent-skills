---
description: Review a pull request end to end (correctness, security, repo conventions, tests) and post ONE consolidated GitHub review with inline comments + a verdict
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(python3:*), Bash(rm:*), Read, Grep, Glob, Write
---

Review a PR end to end using the shared MagmaMoose PR review workflow.

**First, read the full rubric** — it prescribes the review dimensions, severity → verdict
policy, inline-comment anchoring rules, and the exact single-POST submission payload.
It lives at the first of these paths that exists (check in order):

1. `.claude/shared/pr-review.md` — headless runs (Nievah installs it into the PR clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/pr-review.md` — installed as a plugin
3. `shared/pr-review.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

**Hard presentation rules — these hold even if the rubric file cannot be found:**

- Post **exactly ONE review**: a single POST to the pulls reviews API whose `comments[]`
  array carries ALL inline comments, alongside the summary body and the verdict `event`.
  Never post the verdict and the summary as separate reviews; never dribble comments
  one call at a time.
- Anchor every finding to its exact `file:line` as an inline comment where the line is
  in the diff; findings on lines outside the diff go in the body as `path:line` prose.
- The body starts with `## Review summary`. No robot emojis, no "AI review" branding —
  it must read as a code review, not as tool output.
- Never append an attribution footer of any kind ("Generated with …", "Reviewed by …",
  co-author tags). The review speaks for itself.

PR input: $ARGUMENTS
