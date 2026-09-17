# Correlation wiring

This is what makes metrics, logs and traces one stack instead of three tools in one UI: from a spike
on a graph to the trace behind it, from a trace to its logs and its service's metrics, and from a log
line back to its trace. Generate all of it as provisioning YAML. Nothing here is set up by clicking in
Grafana, because anything clicked together is lost with the next replica and never reviewed.

## Contents

- [Prerequisites per signal](#prerequisites-per-signal)
- [Tempo metrics-generator](#tempo-metrics-generator)
- [Datasource provisioning](#datasource-provisioning)
- [Label mapping](#label-mapping)
- [Gotchas](#gotchas)

## Prerequisites per signal

| Link | Needs |
| --- | --- |
| Metric to trace (exemplars) | Prometheus exemplar storage on (`enableFeatures: [exemplar-storage]`, still a feature flag in Prometheus 3.14); applications that attach trace IDs as exemplars; the datasource's `exemplarTraceIdDestinations` |
| Log to trace | A trace ID on the log line. OTLP logs carry `trace_id` as structured metadata in Loki. Logs tailed from files need the application to print it |
| Trace to logs | Loki labels that match span resource attributes (see [Label mapping](#label-mapping)) |
| Trace to metrics, service graph | Tempo's metrics-generator writing span metrics and service graph series into Prometheus |

## Tempo metrics-generator

The metrics-generator turns spans into RED metrics (`span-metrics`) and a service dependency graph
(`service-graphs`), and remote-writes them into Prometheus. Two things must be true on the Prometheus
side:

- The remote write receiver is enabled (`prometheus.prometheusSpec.enableRemoteWriteReceiver: true`
  in kube-prometheus-stack).
- Tempo writes to **each Prometheus replica** by pod DNS name (invariant 13).

Tempo 3.x chart values. Processors are enabled per tenant through the scoped overrides format; Tempo
3.0 refuses to start on the legacy flat overrides keys.

```yaml
tempo:
  metricsGenerator:
    enabled: true
    storage:
      path: /var/tempo/generator/wal
      remote_write:
        - url: http://<prometheus-pod-0>.prometheus-operated.<namespace>.svc:9090/api/v1/write
          send_exemplars: true
        - url: http://<prometheus-pod-1>.prometheus-operated.<namespace>.svc:9090/api/v1/write
          send_exemplars: true
  overrides:
    defaults:
      metrics_generator:
        processors:
          - service-graphs
          - span-metrics
```

Resulting series include `traces_spanmetrics_calls_total`, `traces_spanmetrics_latency_bucket`,
`traces_service_graph_request_total` and `traces_service_graph_request_failed_total`. Check the names
against the deployed version before wiring queries to them.

## Datasource provisioning

One provisioning file (or the chart's datasource list). Fixed `uid` values, because every
cross-reference below is by `uid`.

```yaml
apiVersion: 1
datasources:
  - name: Metrics
    uid: metrics
    type: prometheus
    # thanos-query, not a Prometheus Service: it deduplicates the replica pair
    url: http://thanos-query.<namespace>.svc.cluster.local:9090
    access: proxy
    isDefault: true
    jsonData:
      httpMethod: POST
      exemplarTraceIdDestinations:
        - name: trace_id              # the exemplar label holding the trace ID
          datasourceUid: tempo
          urlDisplayLabel: View trace

  - name: Logs
    uid: logs
    type: loki
    url: http://<loki-read-service>.<namespace>.svc.cluster.local:3100
    access: proxy
    jsonData:
      maxLines: 1000
      derivedFields:
        # OTLP logs: trace_id arrives as structured metadata, matched by name
        - name: TraceID
          matcherType: label
          matcherRegex: trace_id
          datasourceUid: tempo
          url: "$${__value.raw}"
          urlDisplayLabel: View trace
        # File-tailed logs: the trace ID printed in the line itself
        - name: TraceIDInLine
          matcherType: regex
          matcherRegex: '(?:trace_?id|traceId)"?\s*[=:]\s*"?([0-9a-fA-F]{32})'
          datasourceUid: tempo
          url: "$${__value.raw}"
          urlDisplayLabel: View trace

  - name: Traces
    uid: tempo
    type: tempo
    url: http://<tempo-service>.<namespace>.svc.cluster.local:3200
    access: proxy
    jsonData:
      tracesToLogsV2:
        datasourceUid: logs
        spanStartTimeShift: "-5m"
        spanEndTimeShift: "5m"
        filterByTraceID: true
        filterBySpanID: false
        tags:
          - key: k8s.namespace.name
            value: k8s_namespace_name
          - key: service.name
            value: service_name
      tracesToMetrics:
        datasourceUid: metrics
        spanStartTimeShift: "-5m"
        spanEndTimeShift: "5m"
        tags:
          - key: service.name
            value: service
        queries:
          - name: Request rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))
          - name: Error rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags,status_code="STATUS_CODE_ERROR"}[5m]))
          - name: p95 latency
            query: histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{$$__tags}[5m])))
      serviceMap:
        datasourceUid: metrics
      nodeGraph:
        enabled: true
```

With kube-prometheus-stack, the chart creates its own Prometheus datasource. Either point it at
thanos-query and give it `exemplarTraceIdDestinations` through
`grafana.sidecar.datasources`, or turn the default datasource off and provision all of them in
`grafana.additionalDataSources`. Do not leave two default datasources. Turning the default off with
`grafana.sidecar.datasources.defaultDatasourceEnabled: false` also removes the chart's Alertmanager
datasource in the chart versions checked, so provision that one too (`type: alertmanager`,
`jsonData.implementation: prometheus`) if Grafana should show Alertmanager alerts and silences.

## Label mapping

`tracesToLogsV2.tags` maps a span attribute (`key`) to a Loki label (`value`). The Loki label names
depend on how logs arrive, so read them from the running Loki (Grafana's label browser, or
`logcli labels`) instead of guessing:

What decides the names is the protocol logs arrive in, not where they were read from:

- **OTLP into Loki**, including container logs the otel-collector tails with `file_log` and enriches
  with `k8s_attributes`: Loki promotes a default set of resource attributes to index labels,
  replacing dots with underscores: `service.name` becomes `service_name`, `k8s.namespace.name`
  becomes `k8s_namespace_name`, and so on.
- **Loki's push API** from Fluent Bit, Promtail or Alloy's Loki writer: whatever labels that pipeline
  sets, often `namespace`, `pod` and `container`, or prefixed variants. Use those names.

Filtering by trace ID (`filterByTraceID: true`) only finds lines that carry the trace ID, so pair it
with at least a namespace or service label to keep the query cheap.

## Gotchas

- **Escape `$` as `$$` in provisioning files.** Grafana expands environment variables in them, so
  `${__value.raw}` and `$__tags` silently become empty strings unless written `$${__value.raw}` and
  `$$__tags`.
- **The Loki "search" tab in the Tempo datasource is gone.** Do not generate `lokiSearch`.
- **Exemplars need the query path too.** If Grafana's metrics datasource is thanos-query, confirm the
  deployed Thanos version serves the exemplars API through the sidecars, then check a panel.
- **Generator series must exist on every Prometheus replica.** If they exist on one only, invariant
  13 is broken: the service graph and span metrics go missing or gappy whenever that replica restarts
  or falls behind.
