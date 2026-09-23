---
description: The human half of publishing private docs through docs-distributor. Decide what is sensitive and what stands in for it, triage a sync the novelty gate blocked, and onboard a new source, without a real value ever reaching public text
argument-hint: "[triage <run id> | onboard <source checkout> | policy question, or empty to triage the latest blocked run]"
allowed-tools: Bash(docs-distributor:*), Bash(uv:*), Bash(kubectl:*), Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(find:*), Bash(ls:*), Bash(yq:*), Bash(jq:*), Read, Write, Edit, Grep, Glob
---

Anonymise documentation for publication using the shared MagmaMoose docs-anonymise workflow.

**First, read the full workflow.** It holds the replace-or-keep policy, the placeholder
scheme, the triage steps for a blocked run, the rule-writing patterns and the onboarding
steps. It lives at the first of these paths that exists (check in order):

1. `.claude/shared/docs-anonymise.md` (headless runs, installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/docs-anonymise.md` (installed as a plugin)
3. `shared/docs-anonymise.md` (working inside the agent-skills checkout)

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- docs-distributor's `README.md`, for the trust model and the mapping format

Treat target-repository hard rules as blockers.

The rule that matters most, so apply it deliberately: **a real value never goes into public
text.** That covers commits, PR bodies, issues, code comments and chat, and it covers a
pointer to where a leak is as much as the leak itself. The mapping, the run reports and the
proposals are private and stay under `~/.config` and `~/.cache`.

Fail closed: when unsure whether a term identifies the source, map it.
