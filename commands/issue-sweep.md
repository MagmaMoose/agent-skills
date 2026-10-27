---
description: Settle every open issue assigned to you (or in an org or repo) - inventory them, verify each against the code and the live system, then close what is done, superseded or no longer needed, and leave a dated state on the rest
argument-hint: "[scope: assignee, org or repo] [dry-run]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(yq:*), Bash(kubectl:*), Bash(az:*), Bash(aws:*), Bash, Read, Edit, Write, Grep, Glob, Agent
---

Sweep open issues using the shared MagmaMoose issue sweep workflow.

**First, read the full rubric.** It lives at the first of these paths that exists
(check in order):

1. `.claude/shared/issue-sweep.md` — headless runs
2. `${CLAUDE_PLUGIN_ROOT}/shared/issue-sweep.md` — installed as a plugin
3. `shared/issue-sweep.md` — working inside the agent-skills checkout

When an issue's state depends on open pull requests, the PR sweep rubric (`pr-sweep.md`, same
locations) says how to read their checks and threads.

Before changing anything in a repository, read its `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`
and mistakes log, once each. Treat their hard rules as blockers.

**Hard rules — these hold even if the rubric file cannot be found:**

- Decide from the default branch and the live system, not from the board column or old comments.
- Production is read-only while you inspect it. Never test a leaked credential.
- Never copy a private repository's names or details into a public repository.
- Every issue ends closed with a reason, or open with a dated state comment and the right board
  column. Comments read as the owner's own: short, specific, no AI branding.

Input: $ARGUMENTS
