# Kubernetes observability stack

Deploy, review or bring up to standard an HA metrics, logs and traces stack on any Kubernetes
cluster, from one fixed reference architecture: Prometheus with Thanos, Loki, Tempo, OpenTelemetry
collectors, Alertmanager and Grafana. Object storage and the notification sink are pluggable. The
architecture is not.

Output is GitOps manifests: Flux (`HelmRepository`, `HelmRelease`, `Kustomization`) by default,
plain Helm values plus an install order as the fallback.

This file is a router. The detail lives in `k8s-observability-stack/references/`, and templates in
`k8s-observability-stack/assets/`, next to this file. Load a reference when its step needs it.

## Why this workflow exists

A stack like this looks healthy on day one whether or not it is configured correctly. Two
compactors on one bucket, a Service in front of the Prometheus pair, a Loki that never deletes
anything, a Watchdog routed nowhere: each passes every readiness probe and costs data or an outage
weeks later. The workflow is built around a short list of those failure modes
(`references/invariants.md`). Generating YAML is the easy part.

## References

Paths are relative to the `k8s-observability-stack/` directory next to this file.

| File | Read it when |
| --- | --- |
| `references/architecture.md` | Always. Components, replicas, diagrams, scaling to the node count, adapting an existing stack, where charts come from |
| `references/invariants.md` | Always, before generating and again before hand-off |
| `references/storage-model.md` | Sizing any PV, or when a request sizes a PV for history |
| `references/backends.md` | Configuring object storage, auth, notification sinks, the heartbeat or an AI triage webhook |
| `references/distros.md` | Before enabling control-plane scrape targets |
| `references/correlation.md` | Wiring Grafana datasources and Tempo's metrics-generator |
| `references/output.md` | Writing the Flux or Helm output, secrets, and the output README |
| `references/validation.md` | After deploying, and when reviewing a running stack |
| `assets/values/` | Chart values: kube-prometheus-stack, Loki, Tempo, both collectors, the exporters |
| `assets/manifests/` | Raw manifests: Thanos, memcached, event exporter, Grafana's database, secrets |
| `assets/flux/` | Chart sources, a component directory, per-cluster Kustomizations |
| `assets/README.template.md` | The output README |

The assets were rendered against the charts named in `references/architecture.md` when this workflow
was written. They are shapes to adapt, never a source of versions.

## Workflow

### 1. Discover before asking

Read the target repository and, if you have read-only access, the cluster. Infer everything you can:

- GitOps tool and layout: Flux or Argo CD objects, where sources, releases and secrets live, how
  clusters differ.
- What already runs: any existing Prometheus, Thanos, Loki, Tempo, collectors, Grafana, exporters.
  Inventory it against `references/architecture.md`.
- Distro and topology: node labels, taints, pools, and how many schedulable nodes the stack gets.
- StorageClasses, whether they allow expansion, and whether they are node-pinned.
- Ingress controller and domains in use; secret management (External Secrets, SOPS, Vault).
- The target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` and runbooks. Its hard
  rules are blockers and win over this workflow.

Cluster access is read-only: `get`, `describe`, `logs`. Anything that changes state needs explicit
authorisation.

### 2. Ask for what is genuinely unknown, in one batch

Never one question at a time. Only ask what discovery could not answer:

- Cluster distro (k3s, EKS, AKS, GKE, vanilla) and node topology.
- Node pool layout, and whether observability gets a dedicated pool.
- StorageClass, and whether it supports volume expansion.
- Object storage backend and region.
- Notification sink.
- Ingress controller and base domain.
- Retention per signal: metrics raw, 5m and 1h resolution; logs; traces.
- Whether an external heartbeat (dead man's switch) endpoint exists.
- GitOps tool (Flux, Argo CD) or direct Helm.

State what you inferred and where from, so the user can correct it in the same reply. If running
unattended, use these defaults for anything still unknown, record each as an assumption, and put it
in the output README's "Before merging" list:

| Unknown | Default |
| --- | --- |
| StorageClass | The cluster's default class; say whether it is zonal or node-pinned |
| Dedicated node pool | None; no node selectors |
| Retention | Metrics raw 30d, 5m 90d, 1h 365d; logs 30d; traces 7d |
| Heartbeat endpoint | Route and receiver against a placeholder Secret, first item in "Before merging" |
| GitOps tool | The repository's; plain Helm if it has none |
| Log collection | On in the node agent, unless another collector already tails container logs (invariant 16) |
| Control-plane targets | Off, unless the distribution exposes them without node changes (`distros.md`) |
| AI triage webhook | Off |
| Ingress for Grafana | None; say how to port-forward |

### 3. Plan against the invariants

Produce a short plan: components and replicas for the node count found, PV sizes from
`references/storage-model.md`, backend and sink choices, what is kept, replaced or added in an
existing stack, and the version of every chart and image. **Verify versions now, from upstream,
and cite the source.** Your training data is stale, and so are the versions in the assets.

Check the plan against every invariant. Where a request breaks one, follow "How to refuse" in
`references/invariants.md`.

### 4. Generate

Start from `assets/`, follow `references/output.md` for layout and secrets, `references/backends.md`
for the storage and receiver blocks, `references/distros.md` for control-plane targets and
`references/correlation.md` for datasources. The architecture does not change between backends and
sinks, but more than one block does: each consumer's storage config, Loki's schema `object_store`
and compactor `delete_request_store`, the credential wiring (a Secret, or workload identity on every
consumer's ServiceAccount), and the Alertmanager receiver. `references/backends.md` lists them per
backend.

### 5. Validate statically

Render everything you can without touching the cluster: `kustomize build`, `helm template` with the
generated values against the pinned chart version, `flux build kustomization` or `kubeconform`
where available. Then run the pre-hand-off check at the end of `references/invariants.md` against
the rendered output, not the source files, because overlays and value layering change the result.

### 6. Hand off

Write the output README (`references/output.md`) and give the user the short hand-off message
described there. The post-deploy checklist in `references/validation.md` goes in the README, and is
the definition of done once the stack is running.

## Review mode

When asked to review an existing stack rather than build one: run discovery, check the manifests
and (read-only) the cluster against every invariant and the validation checklist, and report
findings ranked by data-loss and outage risk, each with evidence. Generate changes only if asked.

## Hard rules

- Refuse config that breaks an invariant, say which one and why, and say what you generated instead.
- Never size a PV for history. History lives in object storage.
- Never inline a secret. Never invent a secret path, bucket name, domain or version.
- Verify every chart version, image tag and version-dependent behaviour against upstream during the
  run, and cite it.
- The AI triage webhook ships alert context to another service. Wire it only with explicit
  approval, separate from approval of the stack.
- Read-only against live clusters unless the user authorises a change.
- The target repository's own rules win over this workflow.
