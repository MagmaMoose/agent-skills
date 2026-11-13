---
name: global-context-optimise
description: Tune the user-level agent setup that every session on this machine inherits - global instructions, rules, skill listing, plugins, MCP servers, hooks and memory indexes - by measuring what loads by default, then cutting duplicates, stale entries and noise without losing a rule the user wrote.
---

Use the shared MagmaMoose global context optimisation workflow.

Read and follow:
- `shared/global-context-optimise.md`
- The user's global instructions, end to end, before planning anything:
  `$CODEX_HOME/AGENTS.override.md` or `$CODEX_HOME/AGENTS.md` (`CODEX_HOME` defaults to
  `~/.codex`), plus `~/.claude/CLAUDE.md` and `~/.claude/rules/` when Claude Code is installed too.

Treat hard rules written there as blockers.

Expected input:
- A scope hint (one surface, such as memory, MCP servers or skills), or nothing at all, which means
  the whole pass.

## CRITICAL: signal per token, and global lines are paid everywhere

**A smaller context window is not the goal. A higher signal-to-token ratio is.** A line in the
global tier is paid in every session in every repository, and a rule there is the only rule that
reaches every repository. So noise costs more here, and so does a lost rule.

The test for every line that loads by default: **would an agent get this wrong, or spend real
tokens finding it out, if the line were not here?** If not, move it on demand or drop the copy.

## Codex surfaces

- Global instructions: `$CODEX_HOME/AGENTS.override.md` when it exists, otherwise
  `$CODEX_HOME/AGENTS.md`. Only one of the two loads.
- MCP servers: `[mcp_servers.<name>]` in `$CODEX_HOME/config.toml`. `enabled = false` switches one
  off; `enabled_tools` and `disabled_tools` trim its tools without deleting it.
- User skills in `~/.agents/skills/`, custom agents in `$CODEX_HOME/agents/`.
- No context report: estimate words x 1.3 as a tripwire and label the number an estimate.
  Identifier-heavy text tokenises far worse than prose.

## Expected behavior

1. **Inventory** every surface that loads by default, listing secret-bearing config by key name only.
2. **Measure** before changing anything, with probes you can repeat afterwards.
3. **Global instructions**: keep rules for every session, move procedures needed only when something
   happens into an on-demand file behind a pointer, and promote a rule repeated across project
   memories into one global line.
4. **Duplicates and noise**: installed rule files that restate a tool's own instructions, personal
   commands that duplicate a plugin, toolkits paid in every session but used in one project, MCP
   servers connected twice or stuck waiting for authentication, hooks that print into every session.
5. **Memory indexes**: pointers, not content, weighted by how often each project's sessions run.
6. **Verify** with the same probes and report before and after, the edits, every move, and the
   removals left for the user's call with their cost.

## Boundaries

- Never delete a rule the user wrote. Move it and report the move.
- Ask before removing a skill, command, plugin, MCP server, connector or hook.
- Back up every file before editing it. A removal is a move into the archive.
- Never touch auth, signing or secret wiring, and never print a secret value.
- Never edit third-party skills or plugin files in place.
- Idempotent: a second run on a tuned setup changes nothing. Leave global config edits uncommitted.
