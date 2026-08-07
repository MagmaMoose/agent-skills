---
description: Sync ./docs (MkDocs) with the code, sweeping every documentable surface for gaps, then verify with a strict build and report coverage
argument-hint: "[scope hint - a subsystem, a page, or empty for everything that changed]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(ls:*), Bash(comm:*), Bash(sort:*), Bash(mkdocs:*), Bash(python3:*), Bash(uv:*), Bash(uvx:*), Read, Write, Edit, Grep, Glob
---

Bring `./docs` into exact agreement with the code using the shared MagmaMoose docs sync workflow.

**First, read the full rubric** — it prescribes the surface sweep, the per-item completeness
bar, the page architecture, the verification steps, and the coverage report format. It lives at
the first of these paths that exists (check in order):

1. `.claude/shared/update-docs.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/update-docs.md` — installed as a plugin
3. `shared/update-docs.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers. A docs style guide in the target repo wins over
the rubric.

The mechanical checks (orphan pages, broken links, dead anchors, stale source anchors, stubs,
leaked credentials, voice violations) come from `docs-audit.py`, resolved the same way:
`${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. Do the checks by hand and
say so if it isn't there.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Sweep the whole codebase, not just the diff.** The diff tells you what's newly wrong; the
  sweep tells you what was never documented. Walk the 30-surface checklist and give every row a
  status. Report `gap` and `n/a` rows with a reason. Never skip a row silently.
- **Document only what the code does.** Every flag, default, env var, endpoint, status code, and
  limit is read from the source in this run. No invented features, no aspirational behavior, no
  guessed defaults.
- **Depth per item, not just coverage.** Each config key gets type, default, required?, effect,
  and an example. Each endpoint gets auth, params, every response code, and errors. Each guide
  gets prerequisites, runnable steps, verification, and rollback.
- **Published prose reads like a person wrote it.** No em-dashes or en-dashes, no "leverage" /
  "utilize" / "it's worth noting" / "delve", no marketing, no robot emojis, no "AI-generated"
  branding, and **never an attribution footer** ("Generated with...", co-author tags).
- **Never leak secrets** into a published page. Placeholders only.
- **Keep `mkdocs.yml` nav in sync** — every new page in, every deleted page out, reader-journey
  order, no orphans.
- **Verify before reporting.** Run `mkdocs build --strict` (or say precisely which dependency is
  missing and how to install it) and the audit script. Never claim a clean build you didn't run.
- **Write the changes, then show them.** Don't stop to ask permission mid-run. Make the edits,
  build, then report the diff, the coverage matrix, and the gaps.
- **Never commit, push, or open a PR.** End with a dirty working tree and a report, unless
  explicitly told otherwise.

Scope hint: $ARGUMENTS
