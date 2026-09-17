---
description: Deploy, review or scaffold an HA Kubernetes observability stack (Prometheus + Thanos, Loki, Tempo, OpenTelemetry, Alertmanager, Grafana) from a fixed reference architecture with pluggable object storage and notification sinks, as Flux GitOps manifests or plain Helm
argument-hint: "[cluster or repo path, backend and sink hints, or 'review' to audit an existing stack]"
allowed-tools: Bash(kubectl:*), Bash(flux:*), Bash(helm:*), Bash(kustomize:*), Bash(kubeconform:*), Bash(jq:*), Bash(yq:*), Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(find:*), Bash(ls:*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

Build or review a Kubernetes observability stack using the shared MagmaMoose workflow.

**First, read the router in full.** It is short, and it says which reference to load at each step.
It lives at the first of these paths that exists (check in order):

1. `.claude/shared/k8s-observability-stack.md`: headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/k8s-observability-stack.md`: installed as a plugin
3. `shared/k8s-observability-stack.md`: working inside the agent-skills checkout

The references and assets are in the `k8s-observability-stack/` directory next to it. Always load
`references/architecture.md` and `references/invariants.md`; load the others when their step needs
them.

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any runbooks, `COMMON_MISTAKES` or footgun log the repository keeps, and its existing monitoring,
  logging and GitOps layout

Treat target-repository hard rules as blockers. Its layout, secret handling and propose-only
policies win over the workflow.

**Hard rules. These hold even if the references cannot be found:**

- **Refuse config that breaks an invariant**, name it, and say what you generated instead:
  1. One Thanos compactor per bucket. Never scaled for HA.
  2. No offline deduplication or vertical compaction unless explicitly requested, and then only with
     `--deduplication.func=penalty` and an irreversibility warning. Dedup at query time.
  3. With the Thanos sidecar: Prometheus retention of at least 6h, local compaction off (2h min and
     max block duration).
  4. thanos-query finds every StoreAPI through `dnssrv+` against a headless Service.
  5. kube-state-metrics: 1 replica or sharded.
  6. kubernetes-event-exporter: 1 replica and `Recreate`, unless its leader election is on.
  7. Loki `retention_enabled: true` and explicit per-tenant ingestion limits.
  8. Each Loki cache has exactly one backend.
  9. Tempo monolithic; more than one replica only after verifying the deployed version supports it
     (Tempo 3.x does not).
  10. Multi-replica components: required hostname anti-affinity, a PDB with `maxUnavailable: 1`,
      and `maxSurge: 0` on Deployments.
  11. The Watchdog routes to an external heartbeat, never to the human sink.
  12. Grafana has no PV, an external database, and provisioned datasources and dashboards.
  13. Remote write into the Prometheus pair, and alerts from Thanos Ruler or Loki's ruler, reach
      every replica, never one Service.
  14. Thanos Ruler and Prometheus select disjoint rules.
  15. Tail sampling with several gateways needs traceID-aware load balancing in front.
  16. One collector tails each log file.
- **Never size a PV for history.** Every PV is working state; history is in object storage.
- **Verify every chart version, image tag and version-dependent behaviour upstream during the
  run**, and cite it. Do not copy versions from memory or from the assets.
- **Never inline or invent a secret**, bucket, domain or version.
- **The AI triage webhook needs its own explicit approval.** It sends alert context to another
  service.
- **Read-only against live clusters** unless authorised. Never commit, push or open a PR unless
  asked.
- **Always write the output README**: what is deployed, before-merging prerequisites, what each PV
  holds, the node drain procedure, the upgrade order and the validation checklist.

Input: $ARGUMENTS
