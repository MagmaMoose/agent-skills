---
name: pr-triage
description: Triage a GitHub PR by reading all review comments, security findings, code-quality comments, and human feedback, then fixing or responding to each thread.
---

Use the shared MagmaMoose PR triage workflow.

Read and follow:
- `shared/pr-triage.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files

Treat target-repository hard rules as blockers.

Expected input:
- PR number, PR URL, branch name, or enough context to identify the pull request.

## CRITICAL: CI-gate-first triage (READ BEFORE ANY OTHER SECTION)

**The end goal is a green PR that is ready to merge.** Replying "false positive"
and resolving a thread is NOT sufficient if the CI check that flagged it is still
failing. A security gate that blocks merge MUST be addressed with a code change:
either fix the underlying issue or add an inline suppression that the scanner
recognizes. Only then reply and resolve.

This is the most common failure mode — do not fall into the trap of explaining
why a finding is wrong without actually making the CI gate pass.

### Suppression strategy

When a security scanner flags a false positive on a PR that blocks merge:

1. **Find the scanner's suppression syntax.** Common patterns:
   - `# kics-scan disable=<rule-id>` (KICS / Checkov)
   - `// nosemgrep: <rule-id>` (Semgrep)
   - `# nosec` (Bandit)
   - Inline `# trunk-ignore(<linter>/<rule>)` (Trunk)
   - Check the target repo's existing suppressions (grep for `disable=`,
     `nosem`, `nosec`, `suppress`) to find the right pattern.

2. **Add the suppression as close to the flagged line as possible**, with a
   comment explaining why it's a false positive.

3. **Commit, push, and verify the CI check turns green** before replying to
   the thread.

Never dismiss a security alert through the API — dismissal is a human judgment
call. Always fix or suppress inline.

## Expected behavior

1. **Gather all feedback** — review threads (GraphQL), PR reviews, issue comments,
   GHAS code-scanning alerts, CI check results.
2. **Check CI status first** — if any CI check is failing, that is the top
   priority. A failing security gate means you MUST change code (fix or suppress).
3. **Decide whether each thread requires a code change, a reply, or no action.**
   Threads from CI-bot findings that block merge ALWAYS require a code change
   (fix or inline suppression).
4. **Make safe code changes where appropriate.** Commit and push them.
5. **Verify CI** — after pushing fixes, check that the failing check turns green.
6. **Reply clearly to each addressed thread** with the commit SHA and what was done.
7. **Resolve threads only when the issue has genuinely been handled** AND the
   corresponding CI check passes (if applicable).
8. **Produce a final summary** confirming CI status, mergeability, and anything
   still requiring human attention.
