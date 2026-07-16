---
description: Read every PR comment (GHAS, Copilot, code-quality, human), fix the code, reply, and resolve each thread
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Read, Edit, Write, Grep, Glob
---

Triage a PR using the shared MagmaMoose PR triage workflow.

**First, read the full rubric.** It lives at the first of these paths that exists
(check in order):

1. `.claude/shared/pr-triage.md` — headless runs (Nievah installs it into the PR clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/pr-triage.md` — installed as a plugin
3. `shared/pr-triage.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

**Hard presentation rules — these hold even if the rubric file cannot be found:**

- Replies and commit messages read as an engineer's work, not as tool output: no robot
  emojis, no "AI-generated" branding.
- Never append an attribution footer of any kind ("Generated with …", "Fixed by …",
  co-author tags) to comments, replies, or commit messages.

PR input: $ARGUMENTS
