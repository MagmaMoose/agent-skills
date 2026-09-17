# Observability stack: <cluster>

<One paragraph: what this directory deploys, to which cluster(s), with which object storage backend
and notification sink. If anything below is not HA (fewer than three nodes, one Tempo replica), say
so here.>

## What is deployed

| Component | Kind | Replicas | PV | StorageClass | Version |
| --- | --- | --- | --- | --- | --- |
| prometheus (+ thanos-sidecar) | StatefulSet | 2 | 50Gi | <class> | <verified> |
| thanos-query | Deployment | 2 | none | | <verified> |
| thanos-store | StatefulSet | 2 | 50Gi | <class> | <verified> |
| thanos-compactor | StatefulSet | 1 (singleton) | 100Gi | <class> | <verified> |
| thanos-ruler | StatefulSet | 2 | 10Gi | <class> | <verified> |
| alertmanager | StatefulSet | 2 | 1Gi | <class> | <verified> |
| kube-state-metrics | Deployment | 1 | none | | <verified> |
| node-exporter | DaemonSet | per node | none | | <verified> |
| blackbox-exporter | Deployment | 2 | none | | <verified> |
| loki-write / loki-read / loki-backend | StatefulSet / Deployment / StatefulSet | 3 / 2 / 2 | 10Gi / none / 10Gi | <class> | <verified> |
| tempo | StatefulSet | 1 | 10Gi | <class> | <verified> |
| otel-collector / otel-gateway | DaemonSet / Deployment | per node / 2 | none | | <verified> |
| grafana | Deployment | 2 | none (Postgres) | | <verified> |
| memcached | Deployment | 3 | none | | <verified> |
| kubernetes-event-exporter | Deployment | 1 | none | | <verified> |
| x509-certificate-exporter | Deployment (+ DaemonSet) | 1 | none | | <verified> |
| node-problem-detector | DaemonSet | per node | none | | <verified> |

### Deviations from the reference architecture

<Every difference and why. For example: "Tempo runs 1 replica: Tempo 3.x does not support more than
one monolithic instance." or "Fluent Bit stays the log collector; otel-collector file_log is off."
Write "None" if there are none.>

## Before merging

- [ ] Heartbeat endpoint exists and its URL is stored: <path> (invariant 11: without it nothing
      tells you the alert path is dead)
- [ ] Secrets created in <secret store>: <path and property for each, from the ExternalSecrets>
- [ ] Buckets or containers created: <names>
- [ ] `thanos tools bucket verify` clean against the bucket (required for self-hosted S3)
- [ ] <Approvals still open, for example the AI triage webhook>
- [ ] <Anything not verified: live cluster checks, versions, node counts>

## What each PV holds

Every PV here is working state. History lives in object storage.

| PV | Holds | If it is lost |
| --- | --- | --- |
| prometheus | WAL and the last <retention> of 2h blocks | That replica's not-yet-uploaded blocks; the other replica still has them |
| thanos-store | Index headers of bucket blocks | Nothing; rebuilt from the bucket on start, slowly |
| thanos-compactor | Scratch for the compaction in progress | Nothing; the compaction restarts |
| thanos-ruler | Rule results before upload | Recent recording rule results not yet uploaded |
| alertmanager | Notification log and silences | Silences, and duplicate notifications for a while |
| loki-write | WAL and unflushed chunks | Unflushed logs on that pod; covered only when the replication factor (<n>) is above 1 |
| loki-backend | Compactor working directory, index gateway cache | Nothing; rebuilt |
| tempo | WAL, head blocks, metrics-generator WAL | Traces not yet flushed to the bucket |

## Node drain procedure

1. Check first: every PDB in <namespaces> shows at least one allowed disruption
   (`kubectl get pdb -n <namespace>`), the Loki and Tempo rings are healthy, both Prometheus
   replicas are up, and the Alertmanager cluster has all its peers.
2. `kubectl cordon <node>`, then `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`.
   Let the PDBs pace it. Never `--disable-eviction`, never force-delete stack pods.
3. <For node-pinned storage:> pods whose PV is on the node stay Pending until it returns. Do the
   maintenance, `kubectl uncordon <node>`, and wait for them to be Ready.
4. Before the next node: rings healthy, Prometheus replica scraping, every stack pod Ready. One node
   at a time.
5. Node gone for good <with node-pinned storage>: delete the stuck pod's PVC, then the pod, so the
   StatefulSet recreates both elsewhere. See "What each PV holds" for what that costs.

## Upgrade order

Release notes of every version crossed win over this list.

1. CRDs and operators.
2. Readers before writers: thanos-query and thanos-store before the sidecars; loki-read and
   loki-backend before loki-write.
3. thanos-compactor last and alone, after a clean `thanos tools bucket verify`.
4. Tempo, one pod at a time.
5. otel-gateway before the node agents.
6. Grafana last, after backing up its database.
7. memcached whenever.

One component at a time, validation between each.

## Validation

<The checklist from the skill's references/validation.md, with this cluster's service names and
namespaces filled in, and the result of each check once run.>
