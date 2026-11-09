---
description: Deprecated alias for /claude-skills:pr-purge. Runs the same PR purge workflow under the old name
argument-hint: "[org name] [repo filter] [dry-run]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(yq:*), Bash(kubectl:*), Bash(kustomize:*), Bash(helm:*), Bash(terraform:*), Bash(tofu:*), Bash(terragrunt:*), Bash, Read, Edit, Write, Grep, Glob, Agent
---

`/claude-skills:pr-sweep` has been renamed to `/claude-skills:pr-purge`. This alias exists so
existing headless installs and scripts keep working, and it will be removed in a future release.

Say once, before you start, that the command is deprecated and the new name is
`/claude-skills:pr-purge`. Then run the PR purge workflow exactly as the new command defines it.
Read the first of these that exists and follow it in full:

1. `.claude/commands/pr-purge.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/commands/pr-purge.md` — installed as a plugin
3. `commands/pr-purge.md` — working inside the agent-skills checkout

If none of them exist, go straight to the rubric instead, at the first of
`.claude/shared/pr-purge.md`, `${CLAUDE_PLUGIN_ROOT}/shared/pr-purge.md`, or
`shared/pr-purge.md`, and follow that.

Do not duplicate or reinterpret the workflow here. This file only forwards.

Input: $ARGUMENTS
