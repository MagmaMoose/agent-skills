---
name: chargate-security-review
description: After the Chargate security gate finishes on a PR, review the change for the security defects a pattern scanner structurally cannot find, and reply to Chargate's summary comment with the additional findings and their fixes.
---

Use the shared MagmaMoose post-Chargate security review workflow.

Read and follow:
- `shared/chargate-security-review.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

Expected input:
- PR number, PR URL, branch name, or enough context to identify the pull request. Chargate is
  expected to have already run on it.

Expected behavior:
- Locate Chargate's summary comment by its hidden marker `<!-- chargate:pr-summary -->` and
  parse the net-new findings, their rule ids, and the gate result.
- If no such comment exists (the gate never ran, PR commenting is off, or the run was
  `baseline` mode), report which case it is and stop. Do not review blind, and do not post a
  comment under the review marker.
- Review the classes a pattern scanner misses: authorization and multi-tenancy, auth flows and
  token lifetime, secrets reaching a log or error path, SSRF, injection across call boundaries,
  IDOR, race conditions and TOCTOU, crypto misuse that is syntactically fine, supply-chain risk
  beyond a CVE match, over-broad IAM and Kubernetes privilege, data exposure in a response
  shape, missing rate limiting or idempotency, and what the diff enables elsewhere.
- Read the surrounding code, not only the diff. Follow inputs back to their entry point and new
  symbols forward to their callers.
- Deduplicate against Chargate on `file:line` (±3 lines) and on rule intent, never on wording.
  Report how many candidates were dropped.
- Give every finding an exact `file:line`, what an attacker does with it, the concrete fix, a
  severity (`critical` / `high` / `medium` / `low`), and whether it blocks.
- Post exactly ONE PR issue comment carrying `<!-- agent-skills:chargate-security-review -->`:
  find the prior one and `PATCH` it, else `POST`. Never a second comment per run, and no inline
  review comments.
- Include the hidden `agent-skills:findings:v1` JSON block so `pr-triage` can fix the findings
  without re-parsing prose. Include it on a clean review too, with an empty findings array.
- State plainly when there is nothing to add. Silence reads as a review that never ran.
- Never suppress or downplay a real finding to make a gate green, and never dismiss a
  Chargate finding through the API. Disagreement goes in prose, with the reasoning.
