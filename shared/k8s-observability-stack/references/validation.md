# Validation

The post-deploy checklist. The stack is done when every item passes, not when every pod is Ready:
most of the failures this checklist catches happen with every pod Ready.

Run the checks in order. Several depend on the one before. Record the result of each in the output
README or the hand-off, with the command you ran and what it returned.

Metric names below are the current upstream names at the time of writing. Some exporters have added
or dropped a `_total` suffix between versions, so a `{__name__=~"..."}` selector is used where that
happened. If a query returns nothing, check the name against the component's `/metrics` before
concluding the check passed.

## Contents

1. [Object storage is usable](#1-object-storage-is-usable)
2. [Every scrape target is up](#2-every-scrape-target-is-up)
3. [Sidecars are uploading](#3-sidecars-are-uploading)
4. [Store gateways are serving history](#4-store-gateways-are-serving-history)
5. [The compactor is compacting](#5-the-compactor-is-compacting)
6. [Loki's ring is healthy](#6-lokis-ring-is-healthy)
7. [Tempo ingests and returns traces](#7-tempo-ingests-and-returns-traces)
8. [The Watchdog reaches the heartbeat](#8-the-watchdog-reaches-the-heartbeat)
9. [Correlation links resolve in Grafana](#9-correlation-links-resolve-in-grafana)
10. [A test alert reaches the sink](#10-a-test-alert-reaches-the-sink)
11. [Supporting checks](#11-supporting-checks)

## 1. Object storage is usable

Run `thanos tools bucket verify` against the configured bucket, from inside the cluster with the
same `objstore.yml` Secret the stack uses, as a one-off Job or `kubectl run`:

```bash
thanos tools bucket verify --objstore.config-file=/etc/thanos/objstore.yml
```

Without `--repair` it only reports. A clean result lists no issues.

**Mandatory for any self-hosted S3 backend** (SeaweedFS, MinIO, Ceph RGW, anything that is not a
hyperscaler's own service), before trusting it with long-term blocks. It exercises listing and
reading the way the compactor will. On a brand new bucket it has nothing to verify, so run it again
once the compactor has completed its first iterations (check 5), and keep that result.

This also proves the credential works. A synced Secret does not.

## 2. Every scrape target is up

```promql
up == 0
```

must return nothing. Then check the targets that should exist actually do, because a target that
was never discovered does not show up as `0`:

```promql
count by (job) (up)
```

- **Control plane, explicitly.** `apiserver`, `kubelet` (including the cAdvisor endpoint) and
  `coredns` are present. For `kube-scheduler`, `kube-controller-manager`, `kube-etcd` and
  `kube-proxy`: either present and up, or deliberately disabled per `distros.md`. Present and down
  is the failure: a permanently firing `*Down` alert that everyone learns to ignore.
- Every stack component has a target: Prometheus, Alertmanager, thanos-query, thanos-store,
  thanos-compactor, thanos-ruler, the sidecars, loki-write, loki-read, loki-backend, tempo,
  otel-collector, otel-gateway, memcached, grafana, and each supporting exporter.

## 3. Sidecars are uploading

Blocks are cut every two hours, so wait at least three hours after Prometheus starts.

```promql
increase(thanos_shipper_uploads_total[3h]) > 0
```

must return one series **per Prometheus replica**. And:

```promql
increase(thanos_shipper_upload_failures_total[3h]) > 0
```

must return nothing. If uploads are zero with no failures, check invariant 3 (local compaction on
means the sidecar has nothing it is allowed to upload).

## 4. Store gateways are serving history

```promql
thanos_blocks_meta_synced{state="loaded"}
```

is above zero on every store gateway once blocks exist, and

```promql
increase(thanos_bucket_store_block_load_failures_total[1h]) > 0
```

returns nothing. Then prove the read path end to end: in Grafana (thanos-query datasource), query a
range older than Prometheus's local retention and get data. On thanos-query's Stores page, confirm
one sidecar per Prometheus replica, every store gateway, and every ruler (invariant 4).

## 5. The compactor is compacting

```promql
thanos_compact_halted == 1
```

returns nothing, **and**

```promql
increase(thanos_compact_iterations_total[24h]) == 0
```

returns nothing once the compactor has been up a day.

The second check matters more. A compactor failing on every run (full disk, bad credential) retries
on its wait interval and never sets `halted`, so the first check alone passes a compactor that has
never completed anything. Also check
`increase(thanos_compact_group_compactions_failures_total[24h])` is flat.

## 6. Loki's ring is healthy

Every ingester is `ACTIVE` in the ring page of a write pod:

```bash
kubectl -n <ns> port-forward svc/<loki-write-service> 3100:3100
curl -s http://localhost:3100/ring
```

The number of ACTIVE ingesters equals the loki-write replica count, and none is `LEAVING`,
`PENDING` or `Unhealthy`. Also:

- Retention is really deleting. With retention enabled, compactor activity shows up in the
  loki-backend logs and `loki_compactor_*` metrics. Do not trust success counters alone: check that
  a retention marker backlog is not growing, and that the compactor can write its working
  directory (a read-only root filesystem without a writable `/tmp` or working dir breaks the
  sweeper while its success counters still climb).
- A query for recent logs from a workload namespace in Grafana returns lines, and a query spanning
  more than the ingesters' in-memory window returns lines from object storage.
- Ingestion is not rate limited: `rate(loki_discarded_samples_total[15m])` is flat, or its
  `reason` label explains a deliberate limit.

## 7. Tempo ingests and returns traces

- Tempo's ring page (served under Tempo's HTTP port; the exact path depends on the version, so
  check that version's API docs) shows every replica healthy. With one replica, it shows one.
- Send a known trace through the full path, the node agent then the gateway then Tempo, for
  example with `telemetrygen traces --otlp-insecure --traces 1` pointed at the node agent's OTLP
  endpoint, and fetch it by ID through Grafana or Tempo's `/api/traces/<trace-id>`.
- The gateway is not dropping spans:
  `{__name__=~"otelcol_exporter_send_failed_spans(_total)?"}` is flat, and
  `{__name__=~"otelcol_processor_tail_sampling_.*"}` shows decisions being made.
- The metrics-generator is writing: service graph and span metrics series exist in Prometheus
  (`traces_service_graph_request_total`, `traces_spanmetrics_calls_total` or the version's
  equivalents), on **both** Prometheus replicas (invariant 13).

## 8. The Watchdog reaches the heartbeat

- The external heartbeat service shows pings arriving at the configured interval. This is the check
  that counts: look at the heartbeat service, not the cluster.
- In the cluster, `alertmanager_notifications_total{integration="webhook"}` climbs and
  `alertmanager_notifications_failed_total{integration="webhook"}` does not.
- A failure count close to the attempt count usually means the URL is a placeholder or does not
  resolve.

## 9. Correlation links resolve in Grafana

- **Exemplars.** A latency histogram panel on the thanos-query or Prometheus datasource shows
  exemplar markers, and clicking one opens the trace in Tempo. If there are no exemplars at all,
  check that exemplar storage is enabled on Prometheus and that the application emits exemplars.
- **Logs to trace.** A Loki log line carrying a trace ID shows the derived field link, and it
  opens the trace.
- **Trace to logs.** From a span in Tempo, "Logs for this span" runs a Loki query that returns the
  lines for that trace.
- **Trace to metrics.** The span's metrics link returns request rate and latency for the service.
- **Service graph.** Tempo's service graph view renders from the metrics-generator series.

## 10. A test alert reaches the sink

Prove the whole path, rule evaluation to notification sink, with a deliberately firing rule, not
just an Alertmanager API call:

1. Apply a temporary PrometheusRule with a unique name and the labels your routing matches, for
   example `alert: StackValidationTest`, `expr: vector(1)`, `for: 1m`, with the same `severity` as
   a paging alert.
2. Confirm it fires in Prometheus, appears in Alertmanager with the expected receiver, and arrives
   in the notification sink (the Teams channel, the Slack channel, the PagerDuty service).
3. If the AI triage webhook is enabled, confirm it received the same alert.
4. Delete the rule and confirm the resolved notification arrives if `send_resolved` is on.

Also send one through the other rule evaluators: a Loki ruler alert and, if used, a Thanos Ruler
rule. They use different Alertmanager client configuration and fail independently.

If the root route sends to a `null` receiver, a rule that fires into no route passes steps 1 and 2
and never reaches step 3. That is the failure this check exists to find.

## 11. Supporting checks

| Check | Pass |
| --- | --- |
| memcached reachable from Loki and Thanos | `memcached_up == 1` for every pod, `memcached_current_connections` above zero, a nonzero hit rate after an hour of queries |
| Loki chunk cache writes succeed | no "object too large" or item size errors in loki-write logs (memcached `-I`, invariant 8) |
| kube-state-metrics not duplicated | `count(count by (instance) (kube_pod_info))` equals the number of kube-state-metrics shards (invariant 5) |
| Event exporter not duplicated | one pod, and a test event (for example scaling a Deployment) appears once in its sink (invariant 6) |
| x509 exporter sees certificates | `x509_cert_not_after` has series for the Secrets it watches |
| API server certificates probed (self-managed control planes) | `probe_ssl_earliest_cert_expiry{job="apiserver-tls-probe"}` has one series per `default/kubernetes` endpoint |
| Ingress policies admit every caller | with the NetworkPolicies applied, `up` is 1 for every stack target, Grafana's Explore returns data from Thanos, Loki and Tempo, and Tempo's span metrics appear in Prometheus |
| node-problem-detector running on every node | `count(problem_gauge)` or its node condition metrics exist per node |
| PDBs allow a drain | `kubectl get pdb -n <ns>` shows ALLOWED DISRUPTIONS of at least 1 for every stack PDB when healthy |
| Grafana is stateless | no PVC bound to Grafana, two replicas Ready, a dashboard change made in git appears in both |
| Alertmanager is clustered | `alertmanager_cluster_members` equals the replica count on each pod |
