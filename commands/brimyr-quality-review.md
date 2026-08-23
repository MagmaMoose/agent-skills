---
description: After the Brimyr patch-coverage gate finishes, review the quality the number cannot measure (test assertions, mocking, error paths, the uncovered changed lines) and reply on the PR with one idempotent comment carrying the additive findings
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(curl:*), Bash(python3:*), Bash(grep:*), Bash(awk:*), Bash(sed:*), Bash(find:*), Bash(rm:*), Read, Grep, Glob, Write
---

Run the post-Brimyr quality review using the shared MagmaMoose workflow.

**First, read the full rubric** — it prescribes how to resolve Brimyr's verdict (including the
fallbacks for when it posted no comment), the test-quality and code-quality dimensions, how to
judge the uncovered changed lines, the dedup rule, and the exact idempotent comment plus its
machine-readable block. It lives at the first of these paths that exists (check in order):

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

- **Brimyr gates on a number.** Patch coverage says every changed line executed. It says nothing
  about whether anything was asserted. Review past the number: assertion-free tests, tests pinned
  to the implementation, over-mocked tests that would pass with the real dependency deleted, a
  test whose name promises one contract while its assertion enshrines the opposite, missing
  negative/boundary/error cases, flaky constructions, and tests that cannot fail.
- **Brimyr may not have posted a PR comment at all** — on `main` it doesn't. Look for
  `<!-- brimyr:pr-summary -->` and `<!-- brimyr:quality-summary -->`, then fall back to the check
  run, then to `gate_result` / `patch_coverage` / `covered_lines` / `total_lines` read off the
  workflow run. Say which source you used. Never describe a comment that didn't exist, and post
  standalone when there is none.
- **Findings must be additive.** Anything Brimyr, SonarQube, Chargate, or an existing thread
  already reported is a duplicate: suppress it and say how many you dropped. Never restate the
  coverage percentage as a finding.
- **Post exactly ONE comment, and make it idempotent.** It carries
  `<!-- agent-skills:brimyr-quality-review -->`; find the prior one and `PATCH` it, otherwise
  `POST`. Never a second comment per run, never two on a PR.
- **Never soften or drop a real finding because the gate came back green**, and never propose a
  fix whose only effect is to move the percentage. A test written to touch lines without
  asserting is a finding, not a remedy.
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
