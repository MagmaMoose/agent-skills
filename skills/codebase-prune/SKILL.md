---
name: codebase-prune
description: Prune a legacy codebase without changing what it does - find dead code, dead dependencies, dead configuration, duplication and over-abstraction, corroborate every candidate before deleting anything, and ship the result as ranked, independently revertible slices.
---

Use the shared MagmaMoose codebase prune workflow.

Read and follow:
- `shared/codebase-prune.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any `COMMON_MISTAKES` or footgun log the repository keeps
- Any existing cleanup issue, `DEPRECATED.md`, or stalled cleanup PR

Treat target-repository hard rules as blockers. A frozen public API, a stated file layout, a
deprecation policy, a vendored directory that is deliberately not edited, or a "no refactors in
feature PRs" rule in the target repository wins over this workflow.

Expected input:
- A scope hint (a directory, a module, a language, a dimension such as "dead code" or
  "dependencies"), or nothing at all, which means the whole repository.

## CRITICAL: "unused" is a hypothesis, not a finding (READ BEFORE ANY OTHER SECTION)

Every dead-code tool answers one question: *is this reachable from the entrypoints I was told
about, through the edges I can see?* In a legacy repository both halves are usually wrong. The
entrypoint list misses cron entries, queue consumers, webhook targets, Kubernetes `command:`,
Dockerfile `CMD`, and scripts only CI runs. The edges are invisible wherever the system dispatches
on strings: reflection, DI containers, decorators, dynamic imports, ORM hooks, templates,
serialized class names, handler names stored in a database, plugin registries.

So tool output is a **candidate list**. Every candidate is corroborated up the evidence ladder in
section 3 of the rubric before it becomes a finding, and anything you cannot corroborate is
reported `unknown` rather than deleted.

This is a credibility constraint, not a technical one. Report thirty candidates, have four turn out
to be live, and nobody reads the other twenty-six. **The run is judged on its false-positive rate,
not its coverage.**

## Less code is not the goal

Fewer things to hold in your head is. The two diverge: deleting a test file scores brilliantly on
lines removed, and collapsing a four-file indirection chain into one direct call often *adds*
lines and is worth far more. Never lead the report with lines deleted. Lead with the hop chain for
each core flow: how many files you must open, and how many hops you must follow, to understand one
behaviour.

The wrong abstraction costs more than the duplication it replaced, so inlining a bad abstraction
back into its call sites is a legitimate outcome here, not a failure.

## Harvest once, to files

```bash
scripts/cruft-harvest.sh . ./harvest/cruft
```

Resolve it from `${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. Run the
commands by hand and say so if it isn't there. Read `90-tooling.txt` first: it records which
dimensions a real analyser covered and which were covered by grep alone, and that distinction goes
in the deliverable. Never install a tool into the target repository to close a gap; report the
install command.

## Safety net before deletion

- Capture a baseline outside the working tree: build, test, lint, typecheck, and the public-symbol
  surface. Record **counts**, not just exit codes. Fewer tests executed after a change is a
  failure, not a rounding error.
- A red baseline means you cannot prove anything. Say so at the top and fix or quarantine first.
- Before trusting a test, break the code it covers on purpose and watch it go red. Legacy suites
  are full of tests that assert nothing.
- Where nothing covers the region, write characterization tests first: pin what the code does now,
  bugs included, in their own commit, before any deletion.
- Only tier-0 changes are provable without a test. In Python, Ruby, PHP and JavaScript almost
  nothing above local scope qualifies, because attribute access is string-keyed at runtime.

## Expected behavior

1. **Orient** — what the software is, who runs it, whether it is published, what the entrypoints
   are, how large the dynamic-dispatch surface is, and what the safety net actually covers.
2. **Harvest** — one read-only dump to files, with the commit recorded.
3. **Ladder** — every candidate through tiers 0-4, ending in exactly one verdict: `delete`,
   `delete-with-tests`, `deprecate-then-delete`, `keep-and-annotate`, `wiring-bug`, `unknown`.
4. **Catalogue** — the eleven cruft dimensions, from dead symbols through dead CI and feature-flag
   debt to committed build artefacts.
5. **Structure and abstraction** — hop chains, the abstraction smells with their tests, and the
   list of abstractions you deliberately left alone.
6. **Rank and slice** — one kind of change per PR, each independently revertible, riskiest last.
7. **Execute, only within authorisation** — verify each slice against the baseline counts and the
   public-surface diff, and record the restore recipe in every deletion commit.

`wiring-bug` is the highest-value output of the run: code that was *meant* to be reachable and is
not. A route never registered, a flag branch that can never be true, an authorisation check nothing
calls. Those are bugs, often security bugs. Lead the deliverable with them, file them, and never
delete them.

## Boundaries

- Never change behaviour. Bugs found are reported, never fixed inside a prune commit.
- Never delete on one signal, and never present a tool's output as a finding.
- Never delete scar tissue. Run `git log -S` and `git blame` on anything that looks wrong rather
  than merely unused; if an incident is behind it, it stays and it gets the comment it never had.
- Never mix concerns in a commit. Deletions, renames, moves, reformats and refactors are separate.
- Never run a `--fix`, formatter or codemod outside tier 0, on a dirty tree, or without reading the
  resulting diff.
- Never remove a security control because nothing appears to call it. That is a vulnerability
  report.
- Never delete a test to make a change pass. The test is the finding.
- Never install a dependency, rewrite history, force-push, or edit a lockfile by hand.
- Never commit, push, or open a PR unless asked.
- Never claim a dimension is clean when its tool was missing. Say it was covered by grep only.
- Never truncate silently, and make every count in the report reconcile.
