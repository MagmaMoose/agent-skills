---
name: docs-update
description: Sync a repository's ./docs (MkDocs) with the current code, sweeping every documentable surface, closing gaps, verifying with a strict build, and reporting coverage.
---

Use the shared MagmaMoose docs sync workflow.

Read and follow:
- `shared/docs-update.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers. A docs style guide in the target repository
wins over the shared rubric.

Expected input:
- A scope hint (a subsystem, a page, a PR number, "this session's work"), or nothing at all,
  which means everything that changed since the docs were last in sync plus a full gap sweep.

## CRITICAL: sweep the codebase, not just the diff (READ BEFORE ANY OTHER SECTION)

**The end goal is documentation with no gaps, not documentation that matches the last commit.**
Updating only the pages the diff touched is the most common failure mode, and it leaves every
surface that was never documented invisible forever.

Every run does both halves:

1. **Drift** — what the recent changes made wrong. Fix it first, because a page that lies to the
   reader is worse than a page that doesn't exist.
2. **Gaps** — what the codebase exposes that no page mentions. Found by sweeping the code, not by
   reading the diff.

The 30-surface checklist in `shared/docs-update.md` (section 2a) is the sweep. Every row gets a
status: `current`, `updated`, `created`, `gap` (with a reason), or `n/a` (with a reason). "I
didn't look" is not a status, and a row omitted from the report is a silent gap.

## Evidence discipline

- Every documented flag, default, env var, endpoint, status code, permission, and limit was read
  from the source during this run. No exceptions.
- Never invent a feature, extrapolate a default, or document intended behavior.
- Copy exact strings: command names, flag spellings, env var names, and error text are
  character-for-character from the code.
- When something can't be determined, say so on the page or leave it out and list it as a gap.
  Never fill a hole with a plausible guess.
- Anchor reference and architecture pages to their sources with `<!-- sources: path, path -->`
  under the H1, so the next run can detect staleness mechanically.
- Real tokens, keys, internal hostnames, customer data, and production IPs never reach a
  published page. Placeholders only.

## Depth bar

Coverage without depth is a stub farm. Each documented item carries its full contract:

- **Config key**: type, default (the real one), required?, effect, valid values, example,
  precedence, whether it's a secret.
- **CLI command**: synopsis, every flag with type and default, a runnable example with real
  output, exit codes, side effects.
- **Endpoint**: method, path, auth and scope, every parameter, request and response examples,
  every non-2xx status, rate limits, idempotency.
- **Guide**: outcome, prerequisites, runnable numbered steps, how to verify, how to undo, and
  where to look when it fails.
- **Error**: the exact message, what triggers it, how to confirm, the fix.
- **Architecture page**: a Mermaid diagram, component responsibilities, labelled boundaries, and
  failure modes.

## Voice

Published pages read as a staff engineer wrote them. Second person, present tense, active voice,
contractions. **No em-dashes or en-dashes.** No "leverage", "utilize", "it's worth noting",
"delve", "seamlessly", "furthermore". No marketing, no robot emojis, no "AI-generated" branding,
and never an attribution footer of any kind.

## Expected behavior

1. **Resolve coordinates** — repo root, docs system (MkDocs, Docusaurus, Sphinx, or nothing yet),
   and the honest change window (every code commit since `./docs` was last touched).
2. **Inventory the change** — classify each changed file by which reader it affects, and catch
   internal refactors that invalidate paths or symbol names named in existing pages.
3. **Sweep every surface** — the 30-row checklist, using the discovery recipes in the rubric.
4. **Inventory the existing docs** — page list, per-page staleness ranking, plus `docs-audit.py`
   for orphans, broken links, dead anchors, stale source anchors, stubs, and leaked credentials.
5. **Build the coverage matrix** — surface, where it lives in code, where it's documented, status.
6. **Write** — fix wrong pages, then fill gaps, then deepen thin pages. Edit surgically and
   preserve correct human-written prose.
7. **Keep the nav in sync** — every new page in, every deleted page out, reader-journey order,
   zero orphans.
8. **Verify** — `mkdocs build --strict`, the audit script, documented commands actually run
   (read-only invocations only), and a bidirectional env-var check between code and docs.
9. **Report** — the per-page change list, the full coverage matrix, verification results with
   warnings quoted, assumptions made, and gaps ordered by reader impact. No silent truncation.

## Boundaries

- Write the changes, then show them. Don't stop mid-run to ask permission.
- Never commit, push, or open a PR unless explicitly asked. The run ends with a dirty working
  tree and a report.
- Delete a page only when the thing it documents is gone from the code, and list every deletion
  with the evidence. Prefer a deprecation note over silence.
- Never add a dependency to the target repository to make a docs build work. Report the missing
  dependency and the install command instead.
- Never run a documented command that mutates production, deletes data, or spends money. Say
  which examples were verified and which were reasoned about statically.
