---
description: Install the 5-layer context stack in this repo - structural map, lean session context, noise control, persistent memory, and a docs skeleton - then verify the auto-loaded tier against a token budget
argument-hint: "[scope hint - a layer to focus on, a constraint, or empty for the whole stack]"
allowed-tools: Bash(git:*), Bash(ls:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(wc:*), Bash(sed:*), Bash(sort:*), Bash(uniq:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(python3:*), Bash(mkdocs:*), Bash(uv:*), Bash(uvx:*), Read, Write, Edit, Grep, Glob
---

Install the layered context stack in this repository using the shared MagmaMoose context
optimisation workflow.

**First, read the full rubric** — it prescribes the five layers, the file schemas, the token
budget, the access-control levers, the verification steps, and the report format. It lives at the
first of these paths that exists (check in order):

1. `.claude/shared/context-optimise.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/context-optimise.md` — installed as a plugin
3. `shared/context-optimise.md` — working inside the agent-skills checkout

Then read:
- The target repository's existing `CLAUDE.md` — end to end, before planning anything
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The manifest and CI workflow, for the real build, test, lint and run commands

Treat target-repository hard rules as blockers. An existing agent-context convention in the target
repo wins over the rubric.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Signal per token, not fewer tokens.** The test for every line in the auto-loaded tier is
  whether an agent would get it wrong, or pay real tokens to find it out, without the line. A
  `CLAUDE.md` that restates the directory layout is a tax paid every session forever.
- **Never delete a rule from an existing `CLAUDE.md`.** Fold it in. You may move it, split it, or
  tighten it; you may not drop its substance. Report line by line what moved and where to.
- **Never invent a command.** Every build, test, lint and run command you write was read out of
  this repo's manifest, `Makefile`, `justfile` or CI workflow in this run.
- **Auto-loaded means `CLAUDE.md` plus its `@`-imports.** Target the whole tier under ~1,000
  tokens, and measure it before you report. **Never `@`-import `PROJECT_INDEX.json`** — that
  undoes the layer it belongs to.
- **There is no `.claudeignore` in Claude Code.** Don't create one. The real levers are
  `.gitignore`, `.claude/settings.json` permissions (tool names capitalised, `deny` > `ask` >
  `allow`, first match wins), and the `[tooling]` block in `CLAUDE.md`.
- **Don't deny what the repo needs.** A permission rule that blocks a command the test or build
  path runs is a broken repo, not a hardened one. Check each rule before adding it.
- **Idempotent.** A second run must not duplicate sections, re-append the maintenance block, or
  clobber hand-written content.
- **Scaffold `./docs`, don't write it.** Filling the pages is `/claude-skills:docs-update`'s job
  against its own 30-surface sweep. Never introduce a second docs system alongside an existing one.
- **Name only commands that resolve.** Check `~/.claude/commands/` and `.claude/commands/` before
  referencing `/adr` or any other command in the maintenance block.
- **Never write a secret** into a file you create, and never add a dependency to this repo to make
  a layer work. Report the install command instead.
- **Verify before reporting.** Measure the token budget, prove every path in `PROJECT_INDEX.json`
  resolves, and run `mkdocs build` or name the exact missing dependency. Never claim a check you
  didn't run.
- **Write the changes, then show them.** Don't stop mid-run to ask permission. Never commit, push,
  or open a PR — end with a dirty working tree and a report.

Scope hint: $ARGUMENTS
