---
description: Deprecated alias for /claude-skills:docs-update. Runs the same docs sync workflow under the old name
argument-hint: "[scope hint - a subsystem, a page, or empty for everything that changed]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(ls:*), Bash(comm:*), Bash(sort:*), Bash(mkdocs:*), Bash(python3:*), Bash(uv:*), Bash(uvx:*), Read, Write, Edit, Grep, Glob
---

`/claude-skills:update-docs` has been renamed to `/claude-skills:docs-update`, so every workflow
here reads `{noun}-{verb}`. This alias exists so existing headless installs and scripts keep
working, and it will be removed in a future release.

Say once, before you start, that the command is deprecated and the new name is
`/claude-skills:docs-update`. Then run the docs sync workflow exactly as the new command defines
it. Read the first of these that exists and follow it in full:

1. `.claude/commands/docs-update.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/commands/docs-update.md` — installed as a plugin
3. `commands/docs-update.md` — working inside the agent-skills checkout

If none of them exist, go straight to the rubric instead, at the first of
`.claude/shared/docs-update.md`, `${CLAUDE_PLUGIN_ROOT}/shared/docs-update.md`, or
`shared/docs-update.md`, and follow that.

Do not duplicate or reinterpret the workflow here. This file only forwards.

Scope hint: $ARGUMENTS
