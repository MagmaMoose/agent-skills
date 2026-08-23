---
description: After the Brimyr gate finishes, review what its two numbers cannot measure (test assertions, mocking, error paths, the uncovered changed lines) and triage the net-new quality findings it reported without blocking on, then reply on the PR with one idempotent comment carrying the additive findings
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(curl:*), Bash(python3:*), Bash(grep:*), Bash(awk:*), Bash(sed:*), Bash(find:*), Bash(rm:*), Read, Grep, Glob, Write
---

Run the post-Brimyr quality review using the shared MagmaMoose workflow.

**First, read the full rubric** — it prescribes how to resolve Brimyr's verdict (reading its PR
comment first, with fallbacks for when there isn't one), the test-quality and code-quality
dimensions, how to judge the uncovered changed lines, how to triage the net-new quality findings
Brimyr reported and didn't block on, the three dedup axes and the security/quality lane
boundary, and the exact idempotent comment plus its machine-readable block. It lives at the
first of these paths that exists (check in order):

1. `.claude/shared/brimyr-quality-review.md` — headless runs (Nievah installs it into the PR clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/brimyr-quality-review.md` — installed as a plugin
3. `shared/brimyr-quality-review.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Brimyr gates on two numbers, and both are blind in the same direction.** Patch coverage says
  every changed line executed. It says nothing about whether anything was asserted. Review past
  it: assertion-free tests, tests pinned to the implementation, over-mocked tests that would pass
  with the real dependency deleted, a test whose name promises one contract while its assertion
  enshrines the opposite, missing negative/boundary/error cases, flaky constructions, and tests
  that cannot fail.
- **Read Brimyr's PR comment first.** It posts one consolidated comment when `pr_comment: 'true'`,
  carrying both the coverage block (`## Brimyr: Quality Assurance`) and, when quality is on, the
  net-new findings block (`## Brimyr: Net-new findings`). Find it by marker, never by author:
  `<!-- brimyr:pr-summary -->` is the consolidated comment, and `<!-- brimyr:quality-summary -->`
  belongs only to a standalone `brimyr lint` run. `pr_comment` defaults to `false`, so when
  there's no comment fall back to the check run, then to the action outputs off the workflow run
  (`gate_result`, `patch_coverage`, `covered_lines`, `total_lines`, `total_coverage`,
  `quality_gate_result`, `quality_net_new_count`, `quality_blocking_count`, `quality_fail_on`).
  Say which source you used, and never describe a comment you didn't read.
- **Triage the net-new quality findings, don't restate them.** `quality_fail_on` defaults to
  `none`, so a passing Brimyr routinely reports findings it blocked on none of. That list is the
  richest "what to fix in addition" surface on the PR and nobody is looking at it. Judge which of
  them matter and why the rest can wait, promoting one only when you can name the concrete
  failure. Severity there is the **SARIF level** (`error` / `warning` / `note`), which is the
  linter's confidence and not a security band, so never rank by it mechanically.
- **A scan that didn't complete is not a clean PR.** `quality_gate_result: error`, the "the
  quality scan did not complete" line, or the "these linters did not run" warning all mean the
  count is missing rather than zero. Absence of the quality block means the half was never
  enabled. Never write "no quality findings" for any of those.
- **Findings must be additive, across three axes.** Anything Brimyr's coverage output, Brimyr's
  own net-new findings list, SonarQube, Chargate, or an existing thread already reported is a
  duplicate: suppress it and say how many you dropped and against which sources. Never restate a
  gate number (coverage percentage, net-new count) as a finding.
- **Stay in your lane.** Both gates now emit Chargate-derived findings, because Brimyr's quality
  half calls `chargate filter-sarif`. The boundary is the **subject**, not the tool: security
  findings belong to `chargate-security-review`, quality findings to you. Leave a security
  finding alone even when it appeared in Brimyr's listing.
- **Post exactly ONE comment, and make it idempotent.** It carries
  `<!-- agent-skills:brimyr-quality-review -->`; find the prior one and `PATCH` it, otherwise
  `POST`. Never a second comment per run, never two on a PR.
- **Never soften or drop a real finding because the gate came back green**, and never propose a
  fix whose only effect is to move the percentage. A test written to touch lines without
  asserting is a finding, not a remedy. The same holds for the quality half, harder: at
  `quality_fail_on: none` it passes by construction, so "Brimyr didn't block on it" is never an
  argument.
- **Verify before reporting.** Every `file:line` real at the head commit, every quoted string
  copied rather than remembered, no invented flags, markers, or outputs, no padding.
- The comment reads as a human quality review: no em-dashes in the posted text, no robot emojis,
  no "AI review" branding, and **never an attribution footer** of any kind ("Generated with …",
  "Reviewed by …", co-author tags). The only emoji are the severity markers (⛔ / 🟡 / 💬). The
  em-dash rule is about what gets posted to GitHub, matching `pr-review` and
  `chargate-security-review`; it does not apply to this repo's own files.
- This review posts a comment. It does not submit a GitHub review, does not set a status check,
  and does not push code — `pr-triage` fixes what it finds.

PR input: $ARGUMENTS
