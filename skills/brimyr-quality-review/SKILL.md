---
name: brimyr-quality-review
description: After the Brimyr gate finishes on a GitHub PR, review the test and code quality its numbers cannot measure and triage the net-new quality findings it reported without blocking on, then reply on the PR with one idempotent comment carrying the additive findings.
---

Use the shared MagmaMoose post-Brimyr quality review workflow.

Read and follow:
- `shared/brimyr-quality-review.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

Expected input:
- PR number, PR URL, branch name, or enough context to identify the pull request.
- Optionally, the Brimyr run that just finished. The workflow resolves it either way.

## What Brimyr leaves for you

Brimyr is quality assurance and gates on two things:

1. **Patch coverage** — the fraction of the lines this PR changed that the test suite executed,
   against a threshold (80% by default, and not applied at all below `min_lines`).
2. **Net-new quality findings** — optional and off by default, and when on, **report-only out of
   the box**. It doesn't re-implement a linter: it calls `chargate filter-sarif` across a process
   boundary and gates on the counts. `quality_fail_on` defaults to `none`.

Its outputs are `mode`, `gate_result` (`pass` | `fail` | `error`), `patch_coverage`,
`covered_lines`, `total_lines`, `total_coverage`, `quality_gate_result`,
`quality_net_new_count`, `quality_blocking_count`, `quality_fail_on`. It also runs
`sonar-scanner` non-blocking for the quality trend, and posts one consolidated PR comment when
`pr_comment: 'true'`.

The coverage number says every changed line ran, not that anything was asserted. The finding
count says findings exist, not that anyone judged them: with `quality_fail_on: none`, a green
Brimyr routinely ships a list of real PR-scoped defects it blocked on none of. Those two gaps
are this review's subject.

## Expected behavior

- **Read Brimyr's PR comment first, and be honest about the source.** It is the primary source
  and carries both halves of the verdict. Find it by marker, never by author:
  `<!-- brimyr:pr-summary -->` is the consolidated comment (coverage plus, when quality is on,
  net-new findings); `<!-- brimyr:quality-summary -->` belongs only to a standalone `brimyr lint`
  run and is not the normal path. `pr_comment` defaults to `false`, so when there is no comment,
  fall back to the check run and then to the action outputs read off the workflow run. State in
  your comment which source you used, and never describe a comment you did not read.
- **Review test quality**, the dimension coverage cannot measure: a test that executes a line
  without asserting on it, a test pinned to the implementation rather than the behaviour, an
  over-mocked test that would pass with the real dependency deleted, a test whose name and comment
  describe one contract while the assertion enshrines the opposite, missing negative and
  error-path cases, missing boundary cases, a flaky construction (time, ordering, network,
  randomness), and a test that cannot fail. For each one, name the mutation that should break the
  test and doesn't.
- **Review code quality past the number**: duplication the diff introduces, a function doing two
  jobs, a name that lies, an abstraction with one caller, error handling that swallows, a lazy
  import that defers a dependency requirement rather than removing it, dead code, a comment that
  contradicts the code, and complexity you can tie to a named failure path.
- **Judge the uncovered changed lines individually.** A gate at or above threshold can still leave
  the single most dangerous line unexecuted. An uncovered error path is worth more than ten
  covered getters. Note that Brimyr lists uncovered lines only when the gate *failed*, so on a
  pass you have to fetch the coverage report yourself.
- **Triage the net-new quality findings, don't restate them.** With `quality_fail_on: none` a
  passing Brimyr routinely reports findings it did not block on, and nobody is reading them.
  Decide which matter and why the rest can wait; promote one only when you can name the concrete
  failure it causes. Severity there is the **SARIF level** (`error` / `warning` / `note`) — the
  producing linter's confidence, not a security band, so never map it onto your severity markers
  mechanically. And a scan that did not complete (`quality_gate_result: error`, the "did not
  complete" line, or the "these linters did not run" warning) is a tool error, never zero
  findings; an absent quality block means the half was never enabled.
- **Deduplicate across three axes**: Brimyr's coverage output, Brimyr's own net-new findings
  list, and SonarQube — plus Chargate and any existing review thread. Say how many you dropped
  and against which sources. Never restate a gate number as a finding.
- **Stay in your lane.** Brimyr's quality half calls `chargate filter-sarif`, so both gates emit
  Chargate-derived findings. The boundary is the **subject**, not the tool: security findings
  belong to `chargate-security-review`, quality findings to you, even when a security finding
  turns up inside Brimyr's listing.
- **Post exactly one comment, idempotently.** It carries
  `<!-- agent-skills:brimyr-quality-review -->`; find the prior one and `PATCH` it, else `POST`.
  Link Brimyr's comment when there is one, and say the gate comment was absent when there isn't.
  Include the machine-readable findings block so `pr-triage` can act on it, and state plainly
  when nothing was found.
- **Verify before reporting.** Every `file:line` real at the head commit, no invented markers or
  outputs, no padding.

## Hard rules

- Never soften, downgrade, or drop a real finding because the gate came back green. A passing
  percentage is not evidence about any finding you hold, and a passing quality gate is weaker
  still: at the default `quality_fail_on: none` it passes by construction, so "Brimyr didn't
  block on it" is never an argument.
- Never propose a fix whose only effect is to move the percentage. A test that calls the changed
  function and asserts nothing is a finding, not a remedy.
- This workflow posts a comment. It does not submit a GitHub review, set a status check, or push
  code. `pr-triage` fixes what it finds.
- No em-dashes in the posted comment, no robot emojis, no "AI review" branding, and never an
  attribution footer on anything posted. That punctuation rule matches `pr-review` and
  `chargate-security-review`, and applies to GitHub text only, not to this repo's files.
