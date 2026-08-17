---
name: context-optimise
description: Install a layered context stack in a repository - a structural map, a lean auto-loaded session context, noise and access control, persistent memory, and a docs skeleton - so every later agent session there starts with more signal and fewer wasted tokens.
---

Use the shared MagmaMoose context optimisation workflow.

Read and follow:
- `shared/context-optimise.md`
- The target repository's existing `CLAUDE.md` — end to end, before planning anything
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The manifest and CI workflow, for the real build, test, lint and run commands

Treat target-repository hard rules as blockers. An existing agent-context convention in the target
repository wins over the shared rubric.

Expected input:
- A scope hint (one layer, a constraint, a directory), or nothing at all, which means the whole
  five-layer stack.

## CRITICAL: signal per token, not fewer tokens (READ BEFORE ANY OTHER SECTION)

**A smaller context window is not the goal. A higher signal-to-token ratio is.**

The two get confused in both directions, and both directions are expensive. Deleting a 200-token
footguns file measures as a win in this session and costs the same bug three more times next
month. A 4,000-token `CLAUDE.md` that restates the directory layout and paraphrases the manifest
is paid on every session forever and buys nothing.

The test for every line in the auto-loaded tier: **would an agent get this wrong, or spend real
tokens finding it out, if the line were not here?** If not, it belongs on demand or nowhere.

And the failure mode that outranks all the others: **stale content is worse than absent content.**
A missing index costs one search. An index naming a module deleted three months ago costs a wrong
plan and a confident wrong answer.

## The two tiers

- **Auto-loaded** — the root `CLAUDE.md` plus everything it `@`-imports. Paid every session.
  Target the whole tier under ~1,000 tokens, and measure it before reporting.
- **On demand** — everything else under `.claude/`, plus `PROJECT_INDEX.json`, read by path only
  when the task calls for it. Free until used.

`PROJECT_INDEX.json` is never `@`-imported. Importing it converts the index into exactly the tax
it exists to avoid.

## Expected behavior

1. **Read the repo first** — languages, package managers, real build/test/lint/run commands (from
   the manifest and CI, not from memory), entrypoints, where source actually lives, and whatever
   already exists of this stack.
2. **Layer 1, the structural map** — `PROJECT_INDEX.json` at the root: summary, entrypoints,
   meaningful modules with purpose and internal dependencies, a few callgraph highlights, and
   hotspots derived from `git log` rather than instinct. Under ~300 lines. Every path in it must
   resolve.
3. **Layer 2, the session context** — the on-demand files (`ARCHITECTURE_MAP.md`,
   `COMMON_MISTAKES.md`, `QUICK_START.md`, `decisions/`, `sessions/`) and a root `CLAUDE.md` under
   ~500 tokens that imports only the first two. Seed `COMMON_MISTAKES.md` from real evidence (fix
   commits, reverts, explained workaround comments) or leave it empty and say so.
4. **Reconcile `CLAUDE.md` and `AGENTS.md`** — pick one canonical file, make the other point at
   it, and say in both which is which. Two files of record that drift apart are worse than one.
5. **Layer 3, noise and access control** — `.gitignore` for what the build generates,
   `.claude/settings.json` denying secrets (tool names capitalised, `deny` > `ask` > `allow`,
   first match wins), and the `[tooling]` block that trims output *before* it enters context.
   There is no `.claudeignore`; never create one.
6. **Layer 4, persistent memory** — `.claude/sessions/TEMPLATE.md` plus the `decisions/` and
   `sessions/` directories, so the commands that write into them have somewhere to land. Don't
   recreate per-repo commands that already exist globally or in a plugin.
7. **Layer 5, human docs** — scaffold `./docs` and `mkdocs.yml` only. Filling the pages is the
   `docs-update` workflow's job.
8. **Add the maintenance block** to `CLAUDE.md`, naming only commands that actually resolve.
9. **Verify** — measure the auto-loaded tier, prove every index path exists, confirm the deny
   rules don't block the repo's own tooling, run `mkdocs build` or name the missing dependency,
   and check the documented commands exist.
10. **Report** — files created and modified, what moved out of any existing `CLAUDE.md` and where
    to, the measured token budget per file, every check with its real result, what you left out
    and why, and the next run.

## Boundaries

- Never delete a rule from an existing `CLAUDE.md`. Move it and report the move.
- Never invent a build, test or run command. If you can't find one, leave it out and say so.
- Never write a secret, token, internal hostname or production URL into a file you create.
- Never add a dependency to the target repository to make a layer work. Report the install command.
- Never introduce a second docs system alongside one that already exists.
- Idempotent: a second run merges, it does not duplicate or clobber.
- Write the changes, then show them. Don't stop mid-run to ask permission.
- Never commit, push, or open a PR unless explicitly asked. The run ends with a dirty working tree
  and a report.
