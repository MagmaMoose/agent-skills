---
description: Prune a legacy codebase without changing what it does - dead code, dead deps, dead config, duplication and over-abstraction - corroborating every candidate before deletion and shipping ranked, revertible slices
argument-hint: "[scope hint - a directory, a module, a language, a dimension, or empty for the whole repo]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(ls:*), Bash(wc:*), Bash(sed:*), Bash(awk:*), Bash(sort:*), Bash(uniq:*), Bash(comm:*), Bash(diff:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(xargs:*), Bash(bash:*), Bash(npx:*), Bash(node:*), Bash(python3:*), Bash(uv:*), Bash(uvx:*), Bash(go:*), Bash(cargo:*), Bash(make:*), Bash(just:*), Bash(scc:*), Bash(tokei:*), Bash(jscpd:*), Bash(lizard:*), Bash(vulture:*), Bash(ruff:*), Bash(deptry:*), Bash(knip:*), Bash(depcheck:*), Bash(madge:*), Bash(staticcheck:*), Bash(deadcode:*), Bash(periphery:*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

Prune this codebase using the shared MagmaMoose codebase prune workflow.

**First, read the full rubric** — it prescribes the phases, the evidence ladder and its verdicts,
the eleven cruft dimensions, the abstraction smells and the list of abstractions never to collapse,
the slicing rules, the deliverable structure, and the named failure patterns. It lives at the first
of these paths that exists (check in order):

1. `.claude/shared/codebase-prune.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/codebase-prune.md` — installed as a plugin
3. `shared/codebase-prune.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any `COMMON_MISTAKES` or footgun log the repository keeps
- Any existing cleanup issue, `DEPRECATED.md`, or stalled cleanup PR

Treat target-repository hard rules as blockers. A frozen public API, a stated file layout, a
deprecation policy, or a "no refactors in feature PRs" rule in the target repo wins over the rubric.

The read-only evidence harvest comes from `cruft-harvest.sh`, resolved the same way:
`${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. Run the commands by hand and
say so if it isn't there.

```bash
scripts/cruft-harvest.sh . ./harvest/cruft
```

**Hard rules — these hold even if the rubric file cannot be found:**

- **"Unused" is a hypothesis, not a finding.** Every dead-code tool only answers "is this reachable
  from the entrypoints I was told about, through the edges I can see". Both halves are usually
  wrong in a legacy repo: cron, queues, webhooks, `CMD`, CI-only scripts and Kubernetes `command:`
  are missing entrypoints, and reflection, DI, decorators, dynamic imports, ORM hooks, templates
  and handler names stored in a database are invisible edges. **Corroborate every candidate before
  deleting it**, and report `unknown` for anything you cannot.
- **Judge the run on its false-positive rate, not its coverage.** Four wrong findings out of thirty
  and nobody reads the other twenty-six, and the real dead code survives forever.
- **Less code is not the goal; fewer things to hold in your head is.** Never lead with lines
  deleted. Lead with the hop chain per core flow — files opened and hops followed to understand one
  behaviour. Removing indirection often adds lines and is still the most valuable change.
- **The wrong abstraction costs more than duplication.** Inlining a bad abstraction back into its
  call sites is a legitimate outcome.
- **Behaviour-preserving by construction.** Bugs found are reported, never fixed inside a prune
  commit.
- **Safety net before deletion.** Baseline build/test/lint/typecheck **counts** and the public
  symbol surface, captured outside the tree on a clean checkout, and diffed after every slice.
  Fewer tests executed is a failure, not a rounding error. A red baseline proves nothing: say so.
- **Prove the test is a safety net.** Break the covered code on purpose and watch it go red before
  you rely on it. Legacy suites are full of tests that assert nothing.
- **No test, no deletion** — except tier 0 (unused imports and locals, unreachable statements,
  file-local symbols the compiler sees whole). In dynamic languages almost nothing above local
  scope is tier 0.
- **Never delete scar tissue.** `git log -S` and `git blame` anything that looks wrong rather than
  merely unused. If an incident is behind it, it stays and it gets the comment it never had.
- **`wiring-bug` is the best output of the run**: code meant to be reachable that is not. A route
  never registered, a flag branch that can never be true, an auth check nothing calls. Lead with
  these. They are bugs, sometimes vulnerabilities. Never delete them.
- **Never remove a security control** because nothing appears to call it.
- **One kind of change per commit and per PR**, each independently revertible, with the restore
  recipe in the commit body. Deletions, renames, moves, reformats and refactors never share a
  commit.
- **Structure moves last and alone**, `git mv` with no content edits, and only if authorised.
  Moving files destroys `git log --follow` and conflicts with every open PR.
- **Never install anything** into the target repo, edit a lockfile by hand, rewrite history, or
  force-push. Report the install command instead.
- **Never run a `--fix`, formatter or codemod** outside tier 0, on a dirty tree, without reading the
  resulting diff, or outside its own dedicated commit.
- **Never claim a dimension is clean** when its tool was missing. Say it was covered by grep only.
- **Never invent** a path, symbol, tool flag or count.
- **Never inflate severity**, and name what is genuinely well-kept. A report that is all criticism
  gets dismissed.
- **Never truncate silently.** Say what was cut, and make every count reconcile.
- **Never commit, push, or open a PR** unless explicitly asked. End with the deliverable.

Scope hint: $ARGUMENTS
