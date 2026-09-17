# Invariants

These are the configurations that lose data or cause outages while looking healthy on day one.
Check every one before generating, and again against the finished output before hand-off.

Invariants 1 to 12 come with the reference architecture. 13 to 16 are the same class of failure,
found in real stacks built from it.

## Contents

- [How to refuse](#how-to-refuse)
- Metrics: [1 compactor singleton](#1-thanos-compactor-is-a-singleton-per-bucket),
  [2 offline dedup off](#2-vertical-compaction-and-offline-deduplication-are-off),
  [3 sidecar retention](#3-prometheus-retention-and-block-duration-with-the-sidecar),
  [4 dnssrv discovery](#4-thanos-query-discovers-every-replica),
  [5 kube-state-metrics](#5-kube-state-metrics-runs-once-or-sharded),
  [13 every replica](#13-writes-into-an-ha-pair-reach-every-replica),
  [14 ruler rule selection](#14-thanos-ruler-and-prometheus-evaluate-disjoint-rules)
- Logs: [7 retention and limits](#7-loki-retention-and-ingestion-limits-are-explicit),
  [8 caches](#8-each-loki-cache-has-exactly-one-backend),
  [16 one collector](#16-one-collector-tails-each-log-file)
- Traces: [9 Tempo replicas](#9-tempo-runs-monolithic-and-replicas-are-verified),
  [15 tail sampling](#15-tail-sampling-sees-whole-traces)
- Platform: [6 event exporter](#6-kubernetes-event-exporter-runs-once),
  [10 placement](#10-multi-replica-components-survive-a-node),
  [11 Watchdog](#11-the-watchdog-reaches-an-external-heartbeat),
  [12 Grafana](#12-grafana-is-stateless)
- [Pre-hand-off check](#pre-hand-off-check)

## How to refuse

When a request breaks an invariant, do not generate the broken config and do not quietly generate
something else. Say, in this order:

1. Which invariant, and the one-sentence failure it causes.
2. What you generated instead.
3. For invariant 2 only: the exact opt-in change, because that one is allowed on explicit request
   with the warning attached.

Example: "I kept thanos-compactor at 1 replica. Two compactors on one bucket compact and delete
the same blocks, which corrupts history (invariant 1). Its downtime does not affect queries."

## 1. Thanos compactor is a singleton per bucket

**Rule.** Exactly one compactor per bucket. A StatefulSet with `replicas: 1`, or a Deployment with
`strategy: Recreate`. No HPA. No PDB that requires it to be available.

**Why.** Two compactors plan and execute the same compactions, then both delete the source blocks.
The result is overlapping or missing blocks, and the compactor halts or silently loses data. A
Deployment with a rolling update runs two pods for the length of the rollout, which is enough.

**Its downtime is acceptable.** The compactor is not on the query path. While it is down,
retention and downsampling stop and the bucket grows. That is what its alerts are for.

**Sharding is not HA.** More than one compactor on a bucket is only safe when each has a
`--selector.relabel-config` that selects disjoint external label sets, so no block is owned twice.
Two clusters writing one bucket still get one compactor, or disjoint shards.

**Refuse:** `replicas > 1`, an HPA, a RollingUpdate Deployment, or a second cluster running its own
unsharded compactor against the same bucket.

## 2. Vertical compaction and offline deduplication are off

**Rule.** Do not set `--compact.enable-vertical-compaction` or `--deduplication.replica-label` on
the compactor. Setting the replica label alone switches vertical compaction on, so both flags count.
Deduplicate at query time with `--query.replica-label` on thanos-query, using the replica labels the
Prometheus and Ruler instances actually carry (with prometheus-operator, `prometheus_replica` and
`thanos_ruler_replica`).

**Why.** Offline deduplication merges replica blocks and deletes the originals. Thanos documents it
as irreversible. With the default one-to-one merge function it has lost data on HA Prometheus pairs;
the `penalty` function is the one designed for them, and Thanos's own advice for it is to back up
the bucket first. Query-time dedup gives the same result on every query and can be turned off by
removing a flag.

**Opt-in.** Only when the user explicitly asks. Then generate
`--compact.enable-vertical-compaction`, `--deduplication.replica-label=<label>` and
`--deduplication.func=penalty`, and state in the output and README that it is irreversible and
that a bucket backup or `thanos tools bucket verify` pass should precede enabling it.

## 3. Prometheus retention and block duration with the sidecar

**Rule.** Whenever the Thanos sidecar uploads blocks:

- Local retention is at least `6h` (Thanos recommends three times the 2h block duration). Default
  to `12h`.
- Local compaction never touches a block before the sidecar has uploaded it. There are two ways
  that is true, and which one applies depends on versions:
  - **Classic mode:** local compaction off, `--storage.tsdb.min-block-duration=2h` and
    `--storage.tsdb.max-block-duration=2h`. prometheus-operator sets both when the sidecar has an
    object storage config. Plain Prometheus needs the flags.
  - **Delayed compaction:** recent prometheus-operator releases (0.94 at the time of writing), with
    Prometheus 3.9 or later and a sidecar 0.42 or later, keep local compaction on and make
    Prometheus wait for the sidecar's upload marker. `spec.disableCompaction: true` forces classic
    mode.
- The operator decides between the two from `spec.thanos.version`, **not** from the sidecar image
  tag, and that field defaults to the operator's own default Thanos version. Always set
  `thanos.version` to the tag of `thanos.image`. An older sidecar image with an unset version gets
  the new mode it does not support.
- `retentionSize`, if set, stays below the PV size and above what 6h actually uses.

**Why.** The sidecar uploads each 2h block after Prometheus cuts it. If Prometheus compacts blocks
locally before upload, the sidecar sees compacted blocks it does not upload by default, and history
goes missing. Local retention is also the object-storage outage budget: if the bucket is unreachable
for longer than retention, the blocks that were never uploaded are deleted.

**Refuse:** retention under 6h, local compaction on without the delayed-compaction mode, an unset
or mismatched `thanos.version`, or a `retentionSize` small enough to delete blocks before upload.

## 4. Thanos Query discovers every replica

**Rule.** Every StoreAPI endpoint thanos-query uses is discovered through DNS SRV against a
**headless** Service, for example
`dnssrv+_grpc._tcp.<headless-service>.<namespace>.svc.cluster.local`. That applies to the sidecars,
the store gateways and the rulers. Recent Thanos releases deprecate the `--endpoint` flag in favour
of `--endpoint.sd-config` (a YAML list of `address` entries, which accept the same `dnssrv+`
prefix); use whichever the deployed version supports without a deprecation warning.

**Why.** A ClusterIP Service in front of two Prometheus pods hands thanos-query one long-lived gRPC
connection to one pod. Query then sees a single replica, deduplication never happens, and a restart
of that pod leaves a gap. Nothing errors.

**Check.** thanos-query's Stores page, or its endpoint metrics, list one sidecar per Prometheus
replica.

## 5. kube-state-metrics runs once or sharded

**Rule.** `replicas: 1`, or automatic sharding (a StatefulSet where each pod passes its own shard
through `--shard` and `--total-shards`, which the chart's autosharding mode wires up).

**Why.** Two plain replicas each export every object. Every series appears twice with a different
`pod` or `instance` label, so `sum()` doubles and alerts miscount. kube-state-metrics is stateless:
a restart re-lists the API and loses nothing, so a single replica is not a durability risk.

**Refuse:** `replicas > 1` without sharding.

## 6. kubernetes-event-exporter runs once

**Rule.** `replicas: 1` and `strategy: Recreate`. No HPA. More than one replica only with its
`leaderElection.enabled: true` config, verified in the version deployed.

**Why.** Every replica watches the same events and exports them independently, so N replicas deliver
every event N times. The maintained fork (resmoio) does have Lease-based leader election, but it is
off by default, and most example manifests leave it off. A rolling update runs two pods during every
rollout and duplicates events for that window. Set `maxEventAgeSeconds` so a restart does not replay
old events. The exporter is stateless, so one replica loses nothing but the events during a restart.

**Refuse:** `replicas > 1` without leader election, or a RollingUpdate strategy on a single replica.

## 7. Loki retention and ingestion limits are explicit

**Rule.**

- `compactor.retention_enabled: true`, `limits_config.retention_period` set, and the compactor's
  `delete_request_store` pointing at the object store.
- Per-tenant limits set deliberately: `ingestion_rate_mb`, `ingestion_burst_size_mb`,
  `max_global_streams_per_user`, and `per_stream_rate_limit`.

**Why.** `retention_enabled` defaults to `false`. Without it nothing is ever deleted and the bucket
grows forever. The limits are what stop one noisy workload from rate-limiting every other tenant's
logs, or blowing up stream count until ingesters fall over.

**Retention runs in the compactor.** A bucket lifecycle rule is only a backstop. If you add one,
make it longer than the longest `retention_period`, because deleting chunks the index still
references turns into query errors.

**Refuse:** retention not enabled, or no limits block.

## 8. Each Loki cache has exactly one backend

**Rule.** For every cache Loki is configured with (chunks, query results, and any of the other
results caches in use), configure exactly one backend. With the reference architecture that is
memcached for all of them.

**Why.** Configuring memcached and Redis for the same cache makes Loki refuse to start. Configuring
neither silently falls back to an in-process cache that each replica keeps to itself, which is the
worst option with multiple read replicas: low hit rates and more memory per pod.

**Also.** Loki stores whole chunks in the chunk cache, and chunks exceed memcached's default 1MB
item size. Run memcached with `-I` raised (for example `-I 5m`) or cache writes fail quietly.

## 9. Tempo runs monolithic, and replicas are verified

**Rule.** Tempo runs as a single binary, `-target=all`. Before generating more than one replica,
check the Tempo version being deployed and confirm from that version's documentation or release
notes that several `all` instances join one memberlist ring and replicate writes. If you cannot
confirm it, generate one replica and say so in the output and README.

**Why.** Tempo's deployment modes changed across major versions, so the "just add replicas" pattern
is not safe to assume. Several monolithic pods that do not share state each hold part of the traces,
and queries return partial results with no error.

**What was verified when this skill was written (September 2026, Tempo 3.0.3):** Tempo 3.0 removed
the scalable single binary target, and its documentation states that running more than one
`-target=all` instance is not supported, because the backend scheduler is a singleton. Monolithic
mode needs no Kafka; microservices mode (the `tempo-distributed` chart) needs a Kafka-compatible
log and replaces ingesters with block-builders and live-stores. So on Tempo 3.x: **one monolithic
replica**, and HA tracing means the distributed chart plus Kafka, which is outside this reference
architecture. Say that in the output rather than generating three monolithic replicas. Re-check on
every run: a later version can change the answer.

## 10. Multi-replica components survive a node

**Rule.** For every component with more than one replica:

- Required pod anti-affinity on `kubernetes.io/hostname`.
- A PodDisruptionBudget with `maxUnavailable: 1`. Never `minAvailable` equal to the replica count,
  which blocks every drain.
- Deployments with required anti-affinity use `maxSurge: 0` and `maxUnavailable: 1`.

**Why.** Without anti-affinity, two replicas land on one node and one node loss takes both. With
required anti-affinity and a surge pod, a rollout on a pool with no spare node schedules a pod that
can never fit and the rollout waits forever. With node-pinned volumes (local-path, local PVs,
LVM-backed CSI drivers), a pod cannot reschedule off its node at all: it stays Pending until that
node returns or its PVC is deleted. The PDB is what makes drains go one pod at a time so the
application-level replication (Loki RF 3, Tempo's ring, the Prometheus pair) has a copy left.

**Refuse:** a multi-replica component without anti-affinity or a PDB, or a surge rollout with
required anti-affinity.

## 11. The Watchdog reaches an external heartbeat

**Rule.** kube-prometheus-stack's always-firing `Watchdog` alert routes to an external heartbeat
(dead man's switch) receiver, as the first child route, with a short `repeat_interval` (1m to 5m)
and `send_resolved: false`. The heartbeat service alerts when pings stop, with a grace period of
roughly three repeat intervals.

**Why.** Every other alert depends on Prometheus, the rule evaluation, Alertmanager and the
notification path all working. When any of them dies, nothing fires and silence looks like health.
The Watchdog inverts that: silence from it is the alert.

**Also.**

- Never route the Watchdog to the human notification sink.
- If the receiver URL comes from a mounted Secret, a missing Secret keeps Alertmanager pods from
  starting, which takes the whole alert path down. Create the Secret before the rollout.
- If the user has no heartbeat endpoint yet, still generate the route and receiver against a
  placeholder Secret, and make the missing endpoint the first item of the output README.

## 12. Grafana is stateless

**Rule.** No PV. An external database (Postgres, for example a three-instance CloudNativePG
cluster). Datasources, dashboards, and any Grafana-managed alerting provisioned as code. With more
than one replica, configure the unified alerting HA peers through a headless Service.

**Why.** A PV forces a single replica and a `Recreate` rollout, so every upgrade is downtime, and
anything clicked together in the UI is gone with the volume. SQLite cannot be shared between
replicas.

**Refuse:** persistence enabled, SQLite with more than one replica, or datasources set up by hand.

## 13. Writes into an HA pair reach every replica

**Rule.** Two kinds of client talk to a replicated pair, and both address every replica rather than a
load-balanced Service:

- **Remote write into Prometheus** (Tempo's metrics-generator, an OpenTelemetry gateway's metrics
  pipeline): one `remote_write` entry per replica, addressed by pod DNS name through the governing
  headless Service, for example
  `http://prometheus-<name>-0.prometheus-operated.<namespace>.svc:9090/api/v1/write`. The receiving
  Prometheus needs the remote write receiver enabled.
- **Alert delivery into Alertmanager** from anything other than Prometheus (Thanos Ruler, Loki's
  ruler): discover every Alertmanager pod through DNS SRV on the `alertmanager-operated` headless
  Service. Prometheus itself already does this through the operator.

**Why.** Remote write through a Service splits samples between the replicas, so each replica holds a
different, gappy subset: rates on either replica are wrong, and query-time dedup stitches the gaps
into something that looks plausible. For alerts, Alertmanager's documentation says not to load
balance between clients and Alertmanagers but to send to all of them. Its HA design assumes every
instance holds every alert and gossips who has already notified; an alert that reached only one
instance is lost if that instance restarts before notifying.

## 14. Thanos Ruler and Prometheus evaluate disjoint rules

**Rule.** When Thanos Ruler runs, the PrometheusRule objects it evaluates and the ones Prometheus
evaluates are selected by disjoint label selectors. The usual split: rules that need history beyond
local retention, or a view across several Prometheus instances, carry a label such as
`evaluation: thanos-ruler`; Prometheus's rule selector excludes it and the Ruler's selects only it.

**Why.** An empty or catch-all selector on both makes every rule evaluate twice. The copies carry
different external labels, so Alertmanager cannot group them into one notification, and recording
rules write duplicate series. Two defaults make this easy to get wrong:

- In kube-prometheus-stack, Prometheus and Thanos Ruler both default their rule selector to the
  release label, so turning the Ruler on with defaults duplicates every chart rule.
- For the operator, an **empty** selector (`{}`) matches every PrometheusRule, while a **null**
  selector matches none. A `NotIn` expression matches objects that lack the label entirely, which is
  what makes the exclusion on the Prometheus side work.

## 15. Tail sampling sees whole traces

**Rule.** If the gateway tier runs tail sampling with more than one replica, the tier in front of
it (the node collectors) exports through the `load_balancing` exporter (formerly `loadbalancing`) with `routing_key: traceID`,
resolving gateway pods through a headless Service.

**Why.** Tail sampling decides per trace after it has seen the spans. With plain load balancing,
spans of one trace land on different gateway replicas; each replica makes its own decision on a
fragment, and sampled traces come out with holes.

## 16. One collector tails each log file

**Rule.** Exactly one agent tails container log files on a node. If the cluster already runs a log
collector (Fluent Bit, Vector, Grafana Alloy, Promtail), either migrate fully or keep the
otel-collector `file_log` receiver (called `filelog` before 2026) off.

**Why.** Two tails ship every line twice, which doubles Loki ingestion, storage and cost, and makes
every log-based count wrong. It also bypasses whatever processing the existing collector does,
redaction included.

## Pre-hand-off check

Run these against the generated output (or the live cluster, for a review) and fix any hit before
hand-off.

| Invariant | Look for |
| --- | --- |
| 1 | Compactor `replicas` other than 1, a compactor Deployment with RollingUpdate, an HPA targeting it |
| 2 | `enable-vertical-compaction` or `deduplication.replica-label` without an explicit user request |
| 3 | Prometheus `retention` under 6h, `retentionSize` near or above the PV size, `thanos.version` unset or different from the `thanos.image` tag |
| 4 | Any thanos-query endpoint that is not `dnssrv+` against a headless Service |
| 5, 6 | kube-state-metrics with `replicas` above 1 without sharding; event exporter above 1 without leader election, or without `Recreate` |
| 7 | Loki without `retention_enabled: true`, or without ingestion limits |
| 8 | A Loki cache with both or neither backend configured; memcached without a raised `-I` |
| 9 | Tempo `replicas > 1` without a recorded version check |
| 10 | Multi-replica workloads missing required anti-affinity or a PDB; `maxSurge` not 0 alongside required anti-affinity |
| 11 | No `alertname="Watchdog"` route to a heartbeat receiver, or the Watchdog reaching the human sink |
| 12 | Grafana persistence enabled, or datasources not provisioned |
| 13 | A `remote_write` URL pointing at a load-balanced Prometheus Service; a Ruler or Loki ruler sending to one Alertmanager Service instead of SRV discovery |
| 14 | Ruler and Prometheus rule selectors that overlap |
| 15 | Tail sampling with more than one gateway replica and no `load_balancing` exporter in front |
| 16 | `file_log` (or `filelog`) enabled while another collector tails the same files |
