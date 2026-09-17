---
name: k8s-observability-stack
description: Deploy, review or scaffold a production-grade HA observability stack on any Kubernetes cluster (Prometheus with Thanos, Loki, Tempo, OpenTelemetry collectors, Alertmanager, Grafana) from a fixed reference architecture with pluggable object storage (Azure Blob, S3, GCS, OCI, SeaweedFS, any S3-compatible) and notification sinks (Teams, Slack, PagerDuty, Opsgenie, email, webhook), output as Flux HelmRelease and Kustomization manifests or plain Helm. Use it whenever someone wants to set up, deploy, fix, upgrade, audit or scaffold monitoring, logging, tracing, an LGTM or Prometheus stack on Kubernetes, even if they only name one piece of it such as Thanos, Loki or Alertmanager routing.
---

Use the shared MagmaMoose Kubernetes observability stack workflow.

Read and follow:
- `shared/k8s-observability-stack.md`: the router. Read it first, in full.
- `shared/k8s-observability-stack/references/architecture.md`: always
- `shared/k8s-observability-stack/references/invariants.md`: always, before generating and before hand-off
- Then only the reference the current step needs:
  - `references/storage-model.md`: PV sizing, and requests that size a PV for history
  - `references/backends.md`: object storage, auth, notification sinks, heartbeat, AI triage webhook
  - `references/distros.md`: control-plane scrape targets per distribution
  - `references/correlation.md`: Grafana datasources, exemplars, trace to logs and metrics
  - `references/output.md`: Flux or Helm layout, secrets, the output README
  - `references/validation.md`: post-deploy checklist and reviews of running stacks
- `shared/k8s-observability-stack/assets/`: templates to start from, never to copy versions from
- The target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, runbooks, and its existing
  monitoring, logging and GitOps layout

Treat target-repository hard rules as blockers. Its layout and policies win over this workflow.

Expected input: a cluster or repository to deploy into, hints about the object storage backend and
notification sink, or a request to review an existing stack.

## Why this skill exists

This stack looks healthy on day one whether or not it is configured correctly. Two Thanos
compactors on one bucket, a Service in front of the Prometheus pair, a Loki that never deletes
anything, a Watchdog routed nowhere: each passes every readiness probe and costs data or an outage
weeks later. The skill is built around that list of failure modes. Generating YAML is the easy part.

## Hard rules

**Refuse config that breaks an invariant.** Name the invariant, give the one-sentence failure, and
say what you generated instead. The sixteen invariants are in `references/invariants.md`; the
router's hard rules summarise them for when that file cannot be read.

**Never size a PV for history.** Every PV in this stack is a WAL, a cache or scratch space. History
lives in object storage, and a request for a history-sized PV is an error to flag.

**Verify versions during the run.** Chart versions, image tags and version-dependent behaviour
(Tempo's deployment modes, Loki's deployment modes, receiver types) change often. Check upstream and
cite the source. The assets are shapes, not a version source.

**Ask once.** Discover what you can from the repository and the cluster first, then ask for the rest
in a single batch.

**Secrets never inline, never invented.** Workload identity first, then External Secrets or SOPS,
following the repository.

**The AI triage webhook is a separate approval.** It ships alert context and cluster state to
another service.

**Always write the output README**, covering what is deployed, prerequisites before merging, what
each PV holds, the node drain procedure, the upgrade order and the validation checklist.
