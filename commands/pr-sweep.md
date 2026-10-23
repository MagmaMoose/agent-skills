---
description: Clear every open pull request in a GitHub org - inventory them, fix the shared causes first, then merge, close or finish each one, settle the issues that keep re-creating PRs, and report what only the owner can do
argument-hint: "[org name] [repo filter] [dry-run]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(yq:*), Bash(kubectl:*), Bash(kustomize:*), Bash(helm:*), Bash(terraform:*), Bash(tofu:*), Bash(terragrunt:*), Bash, Read, Edit, Write, Grep, Glob, Agent
---

Sweep a GitHub organisation's open pull requests using the shared MagmaMoose PR sweep workflow.

**First, read the full rubric.** It lives at the first of these paths that exists
(check in order):

1. `.claude/shared/pr-sweep.md` — headless runs
2. `${CLAUDE_PLUGIN_ROOT}/shared/pr-sweep.md` — installed as a plugin
3. `shared/pr-sweep.md` — working inside the agent-skills checkout

It uses the PR triage rubric (`pr-triage.md`, same locations) for each PR's review threads and
failing gates; read that too when you reach that step.

Before changing anything in a repository, read its `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`
and mistakes log, once each. Treat their hard rules as blockers.

**Hard rules — these hold even if the rubric file cannot be found:**

- Never bypass branch protection or rulesets (`--admin`, disabling checks, editing settings or
  secrets). Merge only what GitHub allows.
- Never copy a private repository's names or details into a public repository.
- Never enable auto-merge on a PR that applies infrastructure on merge; read its plan first.
- Replies and commit messages read as an engineer's work: no robot emojis, no "AI-generated"
  branding, no attribution footer unless the target repository asks for one.

Input: $ARGUMENTS
