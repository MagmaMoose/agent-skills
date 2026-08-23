---
name: brimyr-quality-review
description: After the Brimyr patch-coverage gate finishes on a GitHub PR, review the test and code quality the coverage number cannot measure, then reply on the PR with one idempotent comment carrying the additive findings.
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

Brimyr gates on **patch coverage**: the fraction of the lines this PR changed that the test suite
executed, against a threshold (80% by default). Its outputs are `mode`, `gate_result`
(`pass` | `fail` | `error`), `patch_coverage`, `covered_lines`, `total_lines`. It also runs
`sonar-scanner` non-blocking for the quality trend.

That number says every changed line ran. It says nothing about whether anything was asserted, and
that gap is this review's subject.

## Expected behavior

- **Resolve the gate's verdict, and be honest about the source.** Look for a Brimyr summary
  comment by marker (`<!-- brimyr:pr-summary -->`, then `<!-- brimyr:quality-summary -->`).
  **Brimyr may not post one at all** — on `main` it does not. Fall back to the check run, then to
  the action outputs read off the workflow run, and state in the comment which source you used.
  Never describe a comment that did not exist.
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
  covered getters.
- **Deduplicate.** Drop anything Brimyr, SonarQube, Chargate, or an existing review thread already
  reported, and say how many you dropped. Never restate the coverage percentage as a finding.
- **Post exactly one comment, idempotently.** It carries
  `<!-- agent-skills:brimyr-quality-review -->`; find the prior one and `PATCH` it, else `POST`.
  When no Brimyr comment exists, post standalone and say the gate comment was absent. Include the
  machine-readable findings block so `pr-triage` can act on it, and state plainly when nothing was
  found.
- **Verify before reporting.** Every `file:line` real at the head commit, no invented markers or
  outputs, no padding.

## Hard rules

- Never soften, downgrade, or drop a real finding because the gate came back green. A passing
  percentage is not evidence about any finding you hold.
- Never propose a fix whose only effect is to move the percentage. A test that calls the changed
  function and asserts nothing is a finding, not a remedy.
- This workflow posts a comment. It does not submit a GitHub review, set a status check, or push
  code. `pr-triage` fixes what it finds.
- No em-dashes in the posted comment, no robot emojis, no "AI review" branding, and never an
  attribution footer on anything posted. That punctuation rule matches `pr-review` and
  `chargate-security-review`, and applies to GitHub text only, not to this repo's files.
