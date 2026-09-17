# Output

What to generate, where to put it, and what the output README must say.

## Contents

- [Pick the format](#pick-the-format)
- [Flux layout](#flux-layout)
- [GitOps rules that bite](#gitops-rules-that-bite)
- [Secrets](#secrets)
- [Plain Helm fallback](#plain-helm-fallback)
- [The output README](#the-output-readme)
- [Hand-off message](#hand-off-message)

## Pick the format

1. **The repository already uses Flux** (Kustomizations under `kustomize.toolkit.fluxcd.io`, a
   `flux-system` directory, `HelmRelease` objects): follow its layout exactly, including where
   `HelmRepository` sources live, how values are layered, how per-cluster differences are expressed
   (overlays, `postBuild` substitution) and how secrets are sourced. The layout below is only for
   repositories without one.
2. **The repository uses Argo CD**: generate the same values files and one `Application` per
   component, ordered with sync waves (operators and CRDs first). Follow the repository's
   ApplicationSet pattern if it has one.
3. **No GitOps**: plain Helm values plus the install order below.

## Flux layout

For a repository with no existing layout. Everything cluster-specific comes from one place so a
second cluster is a new substitution file, not a copy of the tree.

```text
infrastructure/observability/
├── kustomization.yaml
├── namespace.yaml
├── sources/                      # one HelmRepository or OCIRepository per chart source
├── secrets/                      # ExternalSecret or SOPS-encrypted Secret per credential
├── kube-prometheus-stack/        # Prometheus + sidecar, Alertmanager, KSM, node-exporter, Grafana, Thanos Ruler
├── thanos/                       # query, store, compactor
├── memcached/
├── loki/
├── tempo/
├── otel-collector/
│   ├── agent/
│   └── gateway/
├── grafana-database/             # CloudNativePG Cluster, when no external Postgres exists
├── exporters/
│   ├── blackbox-exporter/
│   ├── kubernetes-event-exporter/
│   ├── node-problem-detector/
│   └── x509-certificate-exporter/
└── README.md
clusters/<cluster>/
└── observability.yaml            # Flux Kustomizations: operators, then stack, with dependsOn and postBuild
```

Each component directory holds a `kustomization.yaml`, a `helmrelease.yaml` (or raw manifests) and
its `values.yaml`. Start from `assets/flux/` and `assets/values/`.

## GitOps rules that bite

**CRDs before custom resources.** When one Flux Kustomization contains a custom resource whose CRD
is installed by a HelmRelease in the same Kustomization, the server-side dry-run fails on the first
reconcile and the whole Kustomization fails, not just that object. Every other resource in it stops
reconciling too. Fix it with one of:

- a separate Kustomization for the operators, with `dependsOn` and `wait: true` on the next one;
- shipping the custom resources through the chart that installs the CRDs (kube-prometheus-stack's
  `extraManifests` renders after its CRDs);
- choosing a deployment method with no CRDs (the OpenTelemetry collector chart instead of
  `OpenTelemetryCollector` resources).

A custom resource rendered by a HelmRelease only fails that release, which retries on its own. That
is acceptable; a failing Kustomization is not.

**Helm merges maps and replaces lists.** With layered values (`valuesFrom` several ConfigMaps, or a
base plus overlay), maps deep-merge but a list in a later layer replaces the earlier list entirely.
`extraManifests`, `additionalDataSources`, `extraArgs`, `tolerations` and `remote_write` all
behave this way. Keep each list in exactly one layer and say so in a comment next to it.

**Flux substitution eats `${...}`.** With `postBuild` substitution on a Kustomization, Flux
replaces every `${VAR}` in the rendered manifests, and an undefined variable becomes an empty
string. This stack is full of `${...}` that belong to someone else: Loki and Tempo's
`-config.expand-env` references, Grafana's `$${__value.raw}`, Alertmanager and collector templates.
Annotate every object carrying them with `kustomize.toolkit.fluxcd.io/substitute: disabled`
(`configMapGenerator` `options.annotations` for generated ConfigMaps), or keep substitution off for
that Kustomization. Then check the rendered object in the cluster, not the file in git.

**Immutable StatefulSet fields fail the whole apply.** Changing `volumeClaimTemplates` (a size, a
name) or `serviceName` on a raw-manifest StatefulSet is rejected by the API server, and in a Flux
Kustomization that failure stops every other object in it from reconciling. For StatefulSets whose
volumes are disposable working state (a compactor's scratch, a store gateway's cache), rename the
volume template and annotate the StatefulSet with `kustomize.toolkit.fluxcd.io/force: enabled`:
Flux deletes and recreates it, the pod keeps its name (so a singleton stays a singleton), and the
new pod gets a new PVC of the new size. The old PVC stays behind; list it for cleanup. Never do this
to a volume holding data that is not also somewhere else. A chart-managed StatefulSet fails only its
own HelmRelease, which is recoverable, but still needs the chart's documented resize path.

**Configuration that is only read at start.** Thanos reads its `objstore.yml` once, and a component
whose config lives in a plain (not hash-named) ConfigMap does not restart when it changes. When an
endpoint, bucket or credential changes, make sure every consumer restarts: a hash-named generated
ConfigMap, a checksum or revision annotation bumped in the pod template, or a documented restart
step. Otherwise half the stack keeps writing to the old target with no error.

**Pin everything.** Exact chart versions in every HelmRelease. Verify the current release of each
chart and image while generating, cite where you checked, and never copy a version from memory or
from the assets without checking it.

**HelmRelease defaults worth setting.** `install.crds: CreateReplace` and `upgrade.crds:
CreateReplace` on charts that own CRDs. Remediation retries on install and upgrade. A generous
`timeout` for the first install. `valuesFrom` a generated ConfigMap (with a kustomize name
reference so a values change rolls the release) when values are long; inline `values` when short.

**Alert routes for everything you add.** If the Alertmanager root route sends to a `null` receiver
(common, to drop noisy defaults), every new alert rule you ship needs a route, or it fires into
nothing. Add the route in the same change as the rule.

## Secrets

Never inline a credential in values, manifests or the README.

- Prefer workload identity to static keys (see `backends.md` per backend).
- Otherwise source static credentials through External Secrets Operator from the cluster's secret
  store (Vault, a cloud secret manager), or commit them SOPS-encrypted if that is what the
  repository does. Follow the repository.
- Mount secrets the way each component expects: files for Alertmanager receivers (`*_file`
  fields); environment variables plus `-config.expand-env=true` for Loki and Tempo; a mounted
  `objstore.yml` Secret for Thanos.
- The secret must exist before anything mounts it. A missing mounted Secret keeps pods from
  starting. List every secret path and key the output expects in the README, and tell the user to
  create them before merging.
- A synced ExternalSecret proves only that the secret store returned bytes. Validate the
  credential against the backend (`validation.md`).

## Plain Helm fallback

Generate one values file per chart release, the raw manifests as plain YAML for `kubectl apply`, and
this install order as a script or a README section. Each step waits for the previous one to be
Ready. `helm --wait` does not wait for StatefulSets an operator creates after the release (Prometheus,
Alertmanager, Thanos Ruler), so follow those with `kubectl rollout status statefulset/<name>`.

1. Namespaces and secrets: object storage credentials, notification sink URLs, the heartbeat URL,
   Grafana admin and database credentials.
2. Operators and CRDs: the `prometheus-operator-crds` chart (then install kube-prometheus-stack with
   `crds.enabled: false`), CloudNativePG, opentelemetry-operator if used.
3. The Postgres cluster for Grafana.
4. memcached.
5. kube-prometheus-stack: Prometheus with the sidecar, Alertmanager, kube-state-metrics,
   node-exporter, Grafana, Thanos Ruler.
6. Thanos store and query, then the compactor.
7. Loki.
8. Tempo.
9. The OpenTelemetry gateway, then the node agents.
10. The supporting exporters.
11. The validation checklist.

Chart steps are `helm upgrade --install <release> <repo>/<chart> --version <exact> --namespace <ns>
--values <file>`; raw-manifest steps (Thanos, memcached, the event exporter, the Postgres cluster)
are `kubectl apply -f <file>`. Make the script refuse to run while any `<placeholder>` is left in the
files.

## The output README

Always write a `README.md` in the output directory. It is for the operator who inherits the stack,
so write it about this cluster, not about the skill. Start from `assets/README.template.md`. It
must cover:

1. **What is deployed.** Component, kind, replicas, PV size and StorageClass, version. Every
   deviation from the reference architecture with its reason. Any invariant the user asked to break
   and what was generated instead.
2. **Before merging.** Secrets to create (path and key names), buckets or containers to create,
   the heartbeat endpoint, approvals still outstanding, and anything the output could not verify
   (live cluster access, versions, a Tempo ring check).
3. **What each PV holds**, using the table in `storage-model.md` with the real sizes.
4. **Node drain procedure** (below).
5. **Upgrade order** (below).
6. **Validation**: the checklist from `validation.md` with the real component names filled in.

### Node drain procedure

Include this, adapted to the StorageClass in use. It matters most with node-pinned volumes.

1. Check first: every stack PDB shows at least one allowed disruption
   (`kubectl get pdb -n <ns>`), the Loki and Tempo rings are all ACTIVE, both Prometheus replicas
   are up, and the Alertmanager cluster has all its peers.
2. `kubectl cordon <node>`, then
   `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`. Let the PDBs pace it. Never
   add `--disable-eviction`, and never force-delete stack pods to hurry it.
3. With node-pinned volumes, pods whose PV lives on the node stay Pending until the node comes back.
   That is expected. Do the maintenance, `kubectl uncordon <node>`, and wait for them to be Ready.
4. Before the next node: the rings are healthy again (loki-write replayed its WAL and is ACTIVE),
   the Prometheus replica is scraping and its sidecar serving, and every stack pod is Ready. One
   node at a time.
5. If a node is gone for good with node-pinned volumes: delete the stuck pod's PVC, then the pod,
   so the StatefulSet recreates both elsewhere. Say what that costs per component, using the real
   replication settings: a Loki ingester's unflushed WAL (covered only when the replication factor
   is above 1), a Prometheus replica's not-yet-uploaded blocks (the other replica still has them),
   Tempo's unflushed head blocks, and nothing for the compactor or store.

### Upgrade order

Read the release notes of every version crossed first. They win over this list.

1. CRDs and operators.
2. Readers before writers, so nothing reads a format it does not understand: thanos-query and
   thanos-store before the sidecars; loki-read and loki-backend before loki-write.
3. The Thanos compactor last among the Thanos components, alone, after a clean
   `thanos tools bucket verify`. It rewrites history, so it is the one to be careful with.
4. Tempo as one rolling StatefulSet update, one pod at a time, ring healthy between pods.
5. The OpenTelemetry gateway before the node agents.
6. Grafana last. It migrates its database schema on start, so back the database up first.
7. memcached whenever. A restart costs cache warm-up, nothing else.

One component at a time, and run the validation checklist between components.

## Hand-off message

When the output is written, tell the user, briefly:

- where the output is and which clusters it targets;
- what they must do before merging or applying (the README's "Before merging" list);
- which invariants shaped a request they made, if any;
- what was verified (versions with sources, static validation such as `kustomize build`,
  `helm template`, `flux build`) and what was not (live cluster checks).
