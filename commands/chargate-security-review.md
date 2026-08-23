---
description: After Chargate finishes, review the PR for the security defects a pattern scanner can't see, and reply to its summary comment with the additional findings and their fixes
argument-hint: "[PR number or URL - defaults to the PR for the current branch]"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(grep:*), Bash(sed:*), Bash(rm:*), Read, Grep, Glob, Write
---

Run the post-Chargate security review using the shared MagmaMoose workflow.

**First, read the full rubric** — it prescribes how to locate and parse the Chargate summary
comment, the thirteen review dimensions a scanner structurally misses, the deduplication
method, the severity → verdict policy, and the exact idempotent comment payload. It lives at
the first of these paths that exists (check in order):

1. `.claude/shared/chargate-security-review.md` — headless runs (Nievah installs it into the PR clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/chargate-security-review.md` — installed as a plugin
3. `shared/chargate-security-review.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Anchor on Chargate's own comment.** It is a single PR issue comment carrying the hidden
  marker `<!-- chargate:pr-summary -->`, updated in place on every push. Parse its net-new
  findings, their rule ids, and its gate result before reviewing anything.
- **No Chargate comment, no review.** If that marker isn't on the PR (the gate never ran, PR
  commenting is off, or the run was `baseline` mode, which has no net-new gate), report which
  case it is and **stop**. "Additional to what it found" is undefined without it, and an
  apologetic comment posted under the review marker is indistinguishable next run from a
  review that ran clean.
- **Findings must be additive.** Anything Chargate already reported is a duplicate: drop it,
  and state how many you dropped so the reader knows the check happened. Match duplicates on
  `file:line` (±3 lines) and on rule intent, never on wording.
- **Review what the gate cannot see**, which is the whole point: authorization and tenancy,
  auth and token lifetime, secrets on log and error paths, SSRF, injection across call
  boundaries, IDOR, TOCTOU, crypto misuse, supply chain, IaC privilege, response-shape
  exposure, missing rate limiting or idempotency, and what the diff enables elsewhere.
- **Read the surrounding code, not only the diff.** A review that reads only the diff has
  reproduced the gate's blind spot with a slower tool. Follow inputs back to their entry point
  and new symbols forward to their callers.
- **Post exactly ONE PR issue comment**, carrying `<!-- agent-skills:chargate-security-review -->`.
  Find the prior one and `PATCH` it, else `POST`. Never a second comment per run, and no inline
  review comments (Chargate owns that lane).
- **Every finding carries** exact `file:line`, what an attacker does with it, the concrete fix,
  a severity (`critical` / `high` / `medium` / `low`), and whether it blocks.
- **A clean result must be unambiguous.** Say plainly that you found nothing to add, because
  silence reads as "the review never ran".
- **Never suppress or downplay a real finding to make a gate green.** Not one of Chargate's,
  not one of your own. This one outranks everything else here.
- Never invent a marker, flag, rule id, or file:line. Every claim traces to something you read.
- The comment reads as a human security review: no em-dashes in the posted text, no robot
  emojis, no "AI review" branding, and **never any attribution footer** ("Generated with …",
  "Reviewed by …", co-author tags).

PR input: $ARGUMENTS
