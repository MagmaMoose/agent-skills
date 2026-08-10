---
name: k8s-audit
description: Audit a Kubernetes platform against a world-class bar, grounding every finding in the live cluster as well as the repository, and producing a ranked deliverable with evidence, merge-ordering hazards, and a sequenced roadmap.
---

Use the shared MagmaMoose Kubernetes audit workflow.

Read and follow:
- `shared/k8s-audit.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any `COMMON_MISTAKES` or footgun log the repository keeps
- Prior audits, post-mortems, and the running cleanup or backlog document, if they exist

Treat target-repository hard rules as blockers. A propose-only policy, a documented access path, or
a commit-trailer ban in the target repository wins over this workflow.

Expected input:
- A scope hint (a cluster, an environment, a dimension such as "security" or "DR", a PR number), or
  nothing at all, which means the whole platform: every cluster, repository and live.

## CRITICAL: audit the running cluster, not only the repository (READ BEFORE ANY OTHER SECTION)

**A repository audit and a live-cluster audit find different things. Do both.**

The repository describes intent; the cluster describes reality, and the gap between them is where
the severe findings live. A repository can be clean, reviewed and fully GitOps-managed while the
running cluster has had no alert delivery for a week, because a manifest that merged correctly
references a secret nobody ever created. No amount of reading YAML finds that.

If live access is genuinely unavailable, say so at the top of the deliverable and mark every
finding repo-only. Never let a clean repository imply a healthy cluster.

Start with one read-only harvest per cluster, to files:

```bash
scripts/k8s-harvest.sh <kube-context> ./harvest/<env>
```

Resolve it from `${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. Run the
commands by hand and say so if it isn't there. Harvesting once means every agent reads the same
instant of cluster state instead of hammering the API and disagreeing with each other.

## Read-only by default

Every state-changing operation is propose-only until the user explicitly authorises it, and then
only within the scope they set: `apply`, `edit`, `patch`, `delete`, `scale`, `annotate`, `cordon`,
`drain`, `flux reconcile` or `suspend`, `helm upgrade`, Argo sync, secret writes, image bumps,
`terraform`/`tofu apply`, and any git history rewrite.

`get`, `describe`, `logs`, `top`, `api-resources` and raw GETs are fine. Never harvest secret
values: names, types and ages only.

## Evidence discipline

- Every finding cites **live evidence** (a harvest file or an exact read-only command with its
  output) and **repository evidence** (`path:line`), where each applies.
- Absence of a control is a valid finding, and often the most important one, but only when you say
  where you looked to be sure it is absent.
- Anything about versions, EOL dates, deprecations, CVEs, or "current best practice" is
  **web-verified during the run** and cites what was checked. Training data is stale by
  construction, and a version claim with no source is worse than no version claim.
- Never invent a path, resource name, version or config value. One fabricated `path:line` discredits
  the whole document.
- Where remediation PRs already exist, read the diffs and judge whether each **actually closes the
  gap against live reality**, or is partial, cosmetic, or wrong. The title is not evidence.
- Classify every finding: `new`, `confirms`, `regression`, `falsely-claimed-fixed`, `false-alarm`.
  A hand-maintained checkbox is a claim to verify, never evidence.

## Verify the load-bearing items yourself

Subagents produce confident, well-formatted, wrong findings. Before anything reaches the report,
confirm it first-hand. Section 2 of the rubric has the exact commands and the bad-answer criteria;
the checks that repeatedly find the worst problems are:

- Every not-Running pod and its real container-level reason, plus **how long** it has been that way.
  Weeks-long breakage is a monitoring finding, not a workload finding.
- Secrets that never synced, and what mounts them. When the victims include the alerting stack, the
  platform is blind and cannot report its own blindness.
- GitOps objects reporting `Ready=True` while the workloads they own are down.
- Nodes whose allocatable equals capacity, so the scheduler is told the control plane costs nothing.
- Memory limits set from a measurement rather than above a peak, and `BestEffort` databases.
- Placement that never rendered: verify with `helm template` / `kustomize build` and the live pod
  spec, never by reading the values file that was supposed to set it.
- Controls that exist and are inert: audit-mode policies, PDBs selecting zero pods (or permitting
  zero disruptions and blocking every drain), ServiceMonitors matching nothing, backup schedules
  selecting nothing.
- Backups that have never been restored, and the written RTO/RPO that does not exist.
- Cross-environment drift, especially a lower environment behind production.
- Merge-ordering hazards among open remediation PRs.

## Expected behavior

1. **Orient** — prior audits, agent docs, open issues and PRs, the issue-to-PR map, access, and a
   one-paragraph description of what this platform actually is.
2. **Harvest** — one read-only dump per cluster and environment, to files, with a timestamp.
3. **Verify by hand** — the load-bearing checks above, in the main thread.
4. **Fan out** — roughly a dozen dimensions, each found then adversarially verified, then a
   completeness critic and a tool-alternatives pass with `REPLACE` / `FIX-IN-PLACE` / `VINDICATE`
   verdicts. Give every agent the shared ground prompt from the rubric.
5. **Synthesise** — the main thread writes the deliverable, because it has been living in the data.
6. **Act, only within authorisation** — log uncovered gaps as issues in the owner's voice, open safe
   one-file PRs, and leave everything state-changing as a proposal.

## Boundaries

- Never perform a state-changing operation without explicit authorisation, and record anything
  authorised in an actions-taken section with its verification.
- Never commit, push, or open a PR unless asked.
- Never let severity inflate. Everything critical means nothing is.
- Name what is genuinely world-class, specifically, and early. An audit that is all criticism reads
  as uncalibrated and gets dismissed as such.
- Never truncate silently. If a list was capped, say what was cut and why, and make every count in
  the report reconcile.
- Never recommend a migration without checking its prerequisites against the actual nodes, including
  whether there is a way back in if it fails.
- No secret values in the harvest, the report, or any issue.
