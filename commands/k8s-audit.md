---
description: Audit a Kubernetes platform against a world-class bar, grounded in the live cluster as well as the repo, producing a ranked deliverable with evidence and a sequenced roadmap
argument-hint: "[scope hint - a cluster, an environment, a dimension, or empty for the whole platform]"
allowed-tools: Bash(kubectl:*), Bash(flux:*), Bash(helm:*), Bash(kustomize:*), Bash(argocd:*), Bash(jq:*), Bash(yq:*), Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(ls:*), Bash(sort:*), Bash(diff:*), Bash(bash:*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

Audit this Kubernetes platform using the shared MagmaMoose Kubernetes audit workflow.

**First, read the full rubric** — it prescribes the phases, the hand-verified checks with their
exact commands and bad-answer criteria, the audit dimensions, the deliverable structure, and the
named failure patterns. It lives at the first of these paths that exists (check in order):

1. `.claude/shared/k8s-audit.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/k8s-audit.md` — installed as a plugin
3. `shared/k8s-audit.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any `COMMON_MISTAKES` or footgun log the repository keeps
- Prior audits, post-mortems, and the running cleanup or backlog document

Treat target-repository hard rules as blockers. A propose-only policy or a documented access path
in the target repo wins over the rubric.

The read-only cluster harvest comes from `k8s-harvest.sh`, resolved the same way:
`${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. Run the commands by hand and
say so if it isn't there.

```bash
scripts/k8s-harvest.sh <kube-context> ./harvest/<env>
```

**Hard rules — these hold even if the rubric file cannot be found:**

- **Audit the live cluster, not only the repo.** They find different things. The repo describes
  intent, the cluster describes reality, and the gap is where the severe findings are. If live
  access is unavailable, say so at the top and mark every finding repo-only.
- **Harvest once, to files, per cluster and environment.** Twenty agents each running their own
  `kubectl` saturate the API and produce findings that contradict each other. One harvest anchors
  every finding to the same instant, and the timestamp goes in the report.
- **Read-only by default.** `apply`, `edit`, `patch`, `delete`, `scale`, `annotate`, `drain`,
  `reconcile`, `helm upgrade`, Argo sync, secret writes, image bumps, `tofu apply` and history
  rewrites are **propose-only** until explicitly authorised, and then only within the stated scope.
- **Ground every finding** in live evidence (a harvest file or an exact command with its output)
  **and** repo evidence (`path:line`). Absence of a control is a valid finding only when you say
  where you looked.
- **Web-verify every version, EOL date, deprecation and best-practice claim during the run**, and
  cite what you checked. Your training is stale.
- **Verify load-bearing claims yourself.** Agents produce confident, well-formatted, wrong findings.
  Nothing reaches the report on an agent's word alone.
- **Read the diff of every remediation PR** you credit, and judge whether it actually closes the gap
  against live reality. The title is not evidence. A checkbox in a document is not evidence.
- **Classify every finding**: `new`, `confirms`, `regression`, `falsely-claimed-fixed`,
  `false-alarm`.
- **Never invent** a path, resource name, version, or config value.
- **Lead with what is genuinely world-class**, specifically. An audit that is all criticism is
  uncalibrated and gets dismissed. Equally, do not soften a critical finding or inflate a nit.
- **Never truncate silently.** Say what was cut, and make every count in the report reconcile.
- **No secret values** in the harvest, the report, or any issue. Names, types and ages only.
- **Never commit, push, or open a PR** unless explicitly asked. End with the deliverable.

Scope hint: $ARGUMENTS
