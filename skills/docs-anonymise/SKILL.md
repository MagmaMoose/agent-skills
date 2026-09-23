---
name: docs-anonymise
description: The human half of publishing private documentation through docs-distributor. Decide which terms are sensitive and what stands in for them, triage a sync the novelty gate blocked, write mapping rules that survive the leak gate, and onboard a new source, without a real value ever reaching public text.
---

Use the shared MagmaMoose docs-anonymise workflow.

Read and follow:
- `shared/docs-anonymise.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- docs-distributor's `README.md`, for the trust model and the mapping format

Treat target-repository hard rules as blockers.

Expected input:
- A blocked run to triage (its run id, or nothing for the latest), a source checkout to
  onboard, or a policy question about whether a term should be replaced.

## The two rules that carry most of the value

**A real value never goes into public text.** Not in a commit, a PR body, an issue, a code
comment or a chat message, and neither does a pointer to where a leak is. The mapping, the
run reports and the proposals are private, and they stay under `~/.config` and `~/.cache` on
the maintainer's machine and in the secret store.

**Fail closed.** When unsure whether a term identifies the source, map it. A wrong
"sensitive" costs a stand-in; a wrong "public" publishes a name that no force-push takes
back. Never loosen the gate to get a run through: change the mapping, or allowlist a
verified-public fact with a reason a stranger can check.
