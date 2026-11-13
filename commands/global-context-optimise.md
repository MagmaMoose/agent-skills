---
description: Measure what the user-level setup loads into every session - global instructions, rules, skill listing, plugins, MCP servers, hooks and memory indexes - then cut duplicates, stale entries and noise without losing a rule
argument-hint: "[scope hint - one surface such as memory, plugins or mcp, or empty for the whole pass]"
allowed-tools: Bash(claude:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(sed:*), Bash(sort:*), Bash(head:*), Bash(tail:*), Bash(diff:*), Bash(cp:*), Bash(mkdir:*), Bash(mv:*), Bash(python3:*), Read, Write, Edit, Grep, Glob
---

Tune the user-level agent setup on this machine using the shared MagmaMoose global context
optimisation workflow.

**First, read the full workflow.** It lists every surface that loads by default, how to measure
each one, what to cut, what to move and what to hand back to the user. It lives at the first of
these paths that exists (check in order):

1. `.claude/shared/global-context-optimise.md` (headless runs, installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/global-context-optimise.md` (installed as a plugin)
3. `shared/global-context-optimise.md` (working inside the agent-skills checkout)

Then read `~/.claude/CLAUDE.md` and every file in `~/.claude/rules/` end to end, before planning
anything. Rules written there are blockers.

**Hard rules. These hold even if the workflow file cannot be found:**

- **Measure first, with the same probes after.** `claude -p "/context"` from an empty directory,
  then from the directories where most sessions start. Report measured numbers, not estimates.
- **Never delete a rule the user wrote.** Move procedures and reference material into a directory
  nothing auto-loads (such as `~/.claude/reference/`), leave the rule and a pointer that says when
  to read the file, and report every move line by line. Never put an on-demand file in
  `~/.claude/rules/` and never `@`-import one.
- **Ask before removing a capability.** Skills, commands, plugins, MCP servers, account connectors
  and hooks are the user's call. Report each with its measured cost and the exact command.
- **Back up before you edit.** Copy every file you change into one dated archive directory first.
  A removal is a move into that archive.
- **Never touch auth, signing or secret wiring.** Settings `env` entries, hooks and helper scripts
  that authenticate, sign or fetch secrets stay byte for byte as they are.
- **Never print a secret.** Inventory `env` and `headers` key names only.
- **Never edit third-party skills or plugin files in place.** Report them instead.
- **Memory indexes hold pointers, not content.** Keep every entry, link and line order, keep
  prohibitions and near deadlines in the hooks, re-read the index right before writing it (other
  sessions append to it), and diff the link list against the backup.
- **Idempotent.** A second run on a tuned setup changes nothing. Leave global config edits
  uncommitted.

Scope hint: $ARGUMENTS
