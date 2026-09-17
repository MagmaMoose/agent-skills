# Backends

Object storage and notification sinks plug into a fixed architecture: the components, the routing
tree and the invariants stay the same. What does change with the backend:

- the storage config block of each consumer (Thanos, Loki, Tempo);
- Loki's `schemaConfig` `object_store` and the compactor's `delete_request_store` (`azure`, `s3`,
  `gcs`);
- the credential wiring: a Secret with keys (and the environment variables or `objstore.yml` built
  from it), or workload identity on the ServiceAccount of **every** consumer, listed below;
- for a sink, the Alertmanager receiver block and the Secret it reads.

Every pod that talks to the bucket needs the credential, whichever way it is delivered: the
Prometheus pods (sidecar), Thanos Ruler, thanos-store, thanos-compactor, every Loki component, and
Tempo. thanos-query does not.

Key names below were checked against Thanos 0.42, the grafana-community Loki chart 18.x (Loki 3.7),
the grafana-community Tempo chart 3.0 (Tempo 3.0) and Alertmanager 0.34, in September 2026. Re-check
them against the versions you deploy.

## Contents

- [Rules for every object store](#rules-for-every-object-store)
- [Azure Blob](#azure-blob)
- [AWS S3](#aws-s3)
- [Google Cloud Storage](#google-cloud-storage)
- [OCI Object Storage](#oci-object-storage)
- [SeaweedFS](#seaweedfs)
- [Other S3-compatible stores](#other-s3-compatible-stores)
- [memcached addresses](#memcached-addresses)
- [Rules for every notification sink](#rules-for-every-notification-sink)
- [Receivers](#receivers): Teams, Slack, PagerDuty, Opsgenie, email, webhook
- [Heartbeat](#heartbeat)
- [AI triage webhook](#ai-triage-webhook)

## Rules for every object store

- **One bucket (or container) per consumer**: Thanos, Loki chunks, Loki ruler, Tempo. Retention,
  lifecycle and access differ per signal, and invariant 1 is per bucket.
- **Several clusters, separate buckets**, or one bucket with an external label per cluster and a
  single compactor. Never two unsharded compactors on one bucket.
- **A credential scoped to the stack.** Never reuse a backup system's credential. An observability
  pod is a large attack surface, and it should not be able to read or delete database backups.
- **Auth, in order of preference:** workload identity (per backend below); then static credentials
  from the cluster's secret store through External Secrets, or SOPS if the repository uses it.
  Never in values files.
- **Thanos wants a whole `objstore.yml`.** Render the complete file into a Secret (an External
  Secrets template, or a SOPS-encrypted Secret) and mount it. Loki and Tempo read credentials from
  environment variables when started with `-config.expand-env=true`.
- **Retention runs in the compactors.** A bucket lifecycle rule is a backstop only, longer than the
  longest application retention.
- **Verify before trusting it.** `thanos tools bucket verify` (`validation.md`) proves the
  credential and the API behave. A synced Secret proves nothing.

## Azure Blob

**Use a flat-namespace storage account. Never ADLS Gen2 with hierarchical namespace (HNS).** With
HNS, deleting a block leaves directory objects behind: Thanos then reads the leftovers as partial
uploads (thanos-io/thanos#6412), Mimir's documentation requires HNS off for the same reason, and
Loki fails with "is a directory" errors on its index cache (grafana/loki#19903). HNS is chosen when
the account is created, so check it before anything else.

**Auth.**

- **AKS Workload Identity** (preferred): a user-assigned managed identity with the Storage Blob Data
  Contributor role on the containers, with a federated credential for each consumer's
  ServiceAccount. Each of those ServiceAccounts carries the `azure.workload.identity/client-id`
  annotation and each pod the `azure.workload.identity/use: "true"` label. Thanos, with no key and
  no `user_assigned_id`, uses the Azure default credential chain, which includes workload identity.
  Loki and Tempo need `use_federated_token: true`.
- **Managed identity** on VM-based nodes: `user_assigned_id` (Thanos, Loki, Tempo) or
  `use_managed_identity: true` (Loki, Tempo).
- **Static**: account name plus account key from a Secret. Clusters outside Azure usually end up
  here, because workload identity federation needs the cluster's service account issuer published
  as an OIDC discovery endpoint Azure can reach.

**Thanos** (`objstore.yml`):

```yaml
type: AZURE
config:
  storage_account: <account>
  storage_account_key: <key>        # omit for workload or managed identity
  container: <thanos-container>
  # endpoint: blob.core.windows.net # change only for sovereign clouds
  # user_assigned_id: <client-id>   # managed identity
```

**Loki** (chart values):

```yaml
loki:
  storage:
    type: azure
    bucketNames:
      chunks: <loki-chunks-container>
      ruler: <loki-ruler-container>
    azure:
      accountName: <account>
      accountKey: ${AZURE_STORAGE_ACCOUNT_KEY}   # expanded from the Secret below
      useFederatedToken: false                    # true for workload identity, and drop accountKey
defaults:
  # The chart already passes -config.expand-env=true; confirm it in the rendered args.
  extraEnvFrom:
    - secretRef:
        name: <loki-objstore-secret>
```

**Tempo** (chart values):

```yaml
tempo:
  storage:
    trace:
      backend: azure
      azure:
        container_name: <tempo-container>
        storage_account_name: <account>
        storage_account_key: ${AZURE_STORAGE_ACCOUNT_KEY}
        # use_federated_token: true             # workload identity, drop the key
  extraArgs:
    config.expand-env: "true"
  extraEnvFrom:
    - secretRef:
        name: <tempo-objstore-secret>
```

## AWS S3

**Auth.** IRSA or EKS Pod Identity. Thanos picks both up through its default credential chain when
no keys are set and `aws_sdk_auth` is left false. Loki and Tempo use the AWS SDK default chain when
no keys are set. Static keys from a Secret otherwise.

- **Which ServiceAccounts:** the role (or Pod Identity association) goes on every consumer's
  ServiceAccount: Prometheus (for the sidecar) and Thanos Ruler through kube-prometheus-stack's
  `serviceAccount` values, thanos-store and thanos-compactor (give the raw manifests their own
  ServiceAccounts), Loki's chart ServiceAccount, and Tempo's.
- **IAM actions:** at minimum `s3:ListBucket` on the bucket and `s3:GetObject`, `s3:PutObject` and
  `s3:DeleteObject` on its objects. Check each project's documented policy for the version deployed;
  some examples add more.
- With IRSA the `objstore.yml` holds no credential, so it can be a plain Secret or ConfigMap, and
  Loki and Tempo need no environment variables at all.

**Thanos:**

```yaml
type: S3
config:
  bucket: <bucket>
  endpoint: s3.<region>.amazonaws.com
  region: <region>
  # access_key / secret_key only without IRSA or Pod Identity
```

**Loki:**

```yaml
loki:
  storage:
    type: s3
    bucketNames:
      chunks: <loki-chunks-bucket>
      ruler: <loki-ruler-bucket>
    s3:
      region: <region>
      # endpoint, accessKeyId and secretAccessKey only for static credentials
```

**Tempo:**

```yaml
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: <tempo-bucket>
        endpoint: s3.<region>.amazonaws.com
        region: <region>
```

## Google Cloud Storage

**Auth.** GKE Workload Identity: leave the service account key empty and the client falls back to
Application Default Credentials, which the GKE metadata server answers for the bound service
account. A service account key JSON from a Secret otherwise.

```yaml
# Thanos
type: GCS
config:
  bucket: <bucket>
  # service_account: <key JSON>   only without Workload Identity
```

```yaml
# Loki
loki:
  storage:
    type: gcs
    bucketNames:
      chunks: <loki-chunks-bucket>
      ruler: <loki-ruler-bucket>
```

```yaml
# Tempo
tempo:
  storage:
    trace:
      backend: gcs
      gcs:
        bucket_name: <tempo-bucket>
```

## OCI Object Storage

Use the **S3-compatible API** for all three consumers. Loki and Tempo have no native OCI client, so
this keeps one configuration shape. (Thanos also has a native `type: OCI` provider with instance
principal support, if you want identity-based auth for Thanos alone.)

- **Endpoint:** `https://<namespace>.compat.objectstorage.<region>.oci.customer-oci.com`. The older
  `https://<namespace>.compat.objectstorage.<region>.oraclecloud.com` form still works.
- **Addressing:** path-style works everywhere. Virtual-hosted style needs the separate `vhcompat`
  endpoint and tenancy-unique bucket names, so stick with path-style.
- **Credentials:** a Customer Secret Key, which is an access key and secret key pair.
- **Signature:** SigV4 only. SigV2 is not supported.
- **Region:** set the OCI region. If a client cannot, set `us-east-1`.

Stanzas: as [SeaweedFS](#seaweedfs) below, with this endpoint and `insecure: false`.

## SeaweedFS

Self-hosted, through its S3 API gateway. Treat it as unproven for this workload until it passes the
checks below on the exact version you run.

**Warn first:** if SeaweedFS runs on the cluster whose telemetry it stores, losing that cluster loses
the record of why it was lost. Recommend separate infrastructure, and say so in the output even if
the user proceeds.

**Running the gateway.**

- `weed server -s3` runs master, volume server, filer and S3 gateway together. `weed filer -s3` runs
  a filer plus gateway. `weed s3 -filer=<filer>:8888` runs the gateway alone. The gateway listens on
  port 8333 by default.
- **Always configure credentials.** With no identities configured, the gateway allows anonymous
  access. Pass `-s3.config=/etc/seaweedfs/s3.json` (or `-config` for standalone `weed s3`), with an
  `identities` list of `{name, credentials: [{accessKey, secretKey}], actions}`, or provision users
  from `weed shell`:

  ```text
  s3.configure -user=thanos -access_key=<key> -secret_key=<secret> -actions=Read,Write,List,Tagging -buckets=<thanos-bucket> -apply
  ```

- **Buckets:** `s3.bucket.create -name <bucket>` in `weed shell`, or `CreateBucket` through any S3
  client. One bucket per consumer.

**Client settings.** Path-style addressing (virtual-hosted needs the gateway's `-domainName`), SigV4,
and plain HTTP only inside a trusted network:

```yaml
# Thanos
type: S3
config:
  bucket: <thanos-bucket>
  endpoint: <gateway-host>:8333
  access_key: <key>
  secret_key: <secret>
  insecure: true               # false behind TLS
  signature_version2: false
  bucket_lookup_type: path
```

```yaml
# Loki
loki:
  storage:
    type: s3
    bucketNames:
      chunks: <loki-chunks-bucket>
      ruler: <loki-ruler-bucket>
    s3:
      endpoint: http://<gateway-host>:8333
      accessKeyId: ${S3_ACCESS_KEY_ID}
      secretAccessKey: ${S3_SECRET_ACCESS_KEY}
      s3ForcePathStyle: true
      insecure: true
```

```yaml
# Tempo
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: <tempo-bucket>
        endpoint: <gateway-host>:8333
        access_key: ${S3_ACCESS_KEY_ID}
        secret_key: ${S3_SECRET_ACCESS_KEY}
        insecure: true
        forcepathstyle: true
```

**What to verify, and why.** The Thanos compactor is the heaviest user of the S3 API in this stack:
multipart uploads of large blocks, `ListObjectsV2` over the whole bucket, and ranged GETs. Problems
reported against SeaweedFS with this stack include a compactor upload that got an HTTP 500 and lost
the block (thanos-io/thanos#8548), a GET returning 200 with a short body that crashed Loki's TSDB
shipper on SeaweedFS 4.21 (grafana/loki#21736), a multipart upload failure on 4.21
(seaweedfs/seaweedfs#9149), and zero-byte directory markers left after block deletion (handled from
Thanos 0.42). So:

1. Confirm multipart upload, `ListObjectsV2` and range requests work on the SeaweedFS version in use.
   If `ListObjectsV2` misbehaves, Thanos has `list_objects_version: v1`.
2. **Run `thanos tools bucket verify` before trusting it with long-term blocks.** For any self-hosted
   S3 backend this is a required pre-flight step, not an optional one. Run it again after the
   compactor's first successful iterations, and record both results in the output README.
3. Watch `thanos_objstore_bucket_operation_failures_total` and the compactor alerts for the first
   week.

## Other S3-compatible stores

MinIO, Ceph RGW, Garage, Cloudflare R2 and similar: same stanzas as SeaweedFS, with the endpoint,
TLS and addressing the store requires. Check path-style versus virtual-hosted addressing, SigV4,
multipart upload and `ListObjectsV2` support, and run `thanos tools bucket verify` as a required
pre-flight step for anything self-hosted. Loki's chart still carries a bundled MinIO subchart, but it
is deprecated and scheduled for removal, so do not build on it.

## memcached addresses

- **Thanos store** (`--index-cache.config` and `--store.caching-bucket.config`, type `MEMCACHED`):
  address memcached through DNS SRV on a headless Service, never through a load-balanced Service.
  Thanos documents the `dnssrvnoa+` prefix for this, for example
  `dnssrvnoa+_client._tcp.memcached.<namespace>.svc.cluster.local`, where `client` is the Service
  port name. Raise `max_item_size` in the client config to match memcached's `-I`.
- **Loki chart**, external memcached: set `memcached.enabled: false`, keep `chunksCache.enabled` and
  `resultsCache.enabled` true, and set each one's `addresses` to the same kind of SRV address. Also
  set `loki.query_range.cache_results: true`.

## Rules for every notification sink

- Every sink is an Alertmanager receiver. The routing tree stays the same when the sink changes.
- Secrets go in files: mount a Secret with `alertmanagerSpec.secrets` (it appears under
  `/etc/alertmanager/secrets/<secret>/<key>`) and use the receiver's `*_file` field. The Secret must
  exist before Alertmanager starts, or the pods do not start (invariant 11).
- `send_resolved: true` for human sinks, `false` for the heartbeat.
- If the root route goes to a `null` receiver, add a route for every alert the stack ships.

## Receivers

**Microsoft Teams.** Use `msteamsv2_configs` (Alertmanager 0.28 and later) with a Power Automate
Workflows webhook ("Post to a channel when a webhook request is received"). The older
`msteams_configs` receiver targets Office 365 connector webhooks, which Microsoft retired in May
2026, so never generate it. The flow belongs to the account that created it; record the owner.

```yaml
receivers:
  - name: teams
    msteamsv2_configs:
      - send_resolved: true
        webhook_url_file: /etc/alertmanager/secrets/<secret>/<key>
```

**Slack.** An incoming webhook through `api_url_file`, or a bot token through `app_token_file` with
`app_url`.

```yaml
  - name: slack
    slack_configs:
      - send_resolved: true
        api_url_file: /etc/alertmanager/secrets/<secret>/<key>
        channel: "#alerts"
```

**PagerDuty.** Events API v2 through `routing_key_file`. `service_key_file` is the legacy
integration.

```yaml
  - name: pagerduty
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/<secret>/<key>
```

**Opsgenie.** `api_key_file`. Atlassian ends Opsgenie on 5 April 2027, so steer new installs to its
replacement and flag existing ones.

```yaml
  - name: opsgenie
    opsgenie_configs:
      - api_key_file: /etc/alertmanager/secrets/<secret>/<key>
```

**Email.**

```yaml
  - name: email
    email_configs:
      - to: <team@example.org>
        from: <alertmanager@example.org>
        smarthost: <smtp-host>:587
        auth_username: <user>
        auth_password_file: /etc/alertmanager/secrets/<secret>/<key>
        require_tls: true
```

**Generic webhook.**

```yaml
  - name: webhook
    webhook_configs:
      - send_resolved: true
        url_file: /etc/alertmanager/secrets/<secret>/<key>
```

## Heartbeat

The Watchdog route (invariant 11) is the first child route:

```yaml
route:
  receiver: <default-receiver>
  routes:
    - receiver: heartbeat
      matchers:
        - alertname = "Watchdog"
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m
receivers:
  - name: heartbeat
    webhook_configs:
      - send_resolved: false
        url_file: /etc/alertmanager/secrets/<secret>/<key>
```

Any service that alerts when a URL stops being called works. healthchecks.io accepts a POST to
`https://hc-ping.com/<uuid>`; Grafana IRM has an Alertmanager heartbeat integration. Set the
service's grace period to about three repeat intervals, and route its own alert somewhere that does
not depend on this cluster.

## AI triage webhook

Optional, and a **separate approval question** from the rest of the stack. An AI triage tool
receives alert labels and annotations (namespaces, pod names, error text) and usually fetches more
cluster state, logs and metrics, then sends all of it to a model that is often an external service.
Ask for explicit approval, and record what leaves the cluster, where it is processed, and how long
it is kept.

- Route it as an extra child route with `continue: true`, so it never takes alerts away from the
  human sink, and scope it with matchers (for example critical severity only) so less leaves.
- **Check that the tool accepts Alertmanager webhooks at all.** For example, HolmesGPT (at 0.42)
  exposes no endpoint for Alertmanager webhook payloads: it pulls from Alertmanager with
  `holmes investigate alertmanager`, and push delivery goes through Robusta's runner at
  `/api/alerts`. Never wire a receiver at an endpoint that does not exist; it fails every
  notification and nobody reads that metric.

```yaml
route:
  routes:
    - receiver: heartbeat
      matchers:
        - alertname = "Watchdog"
    - receiver: ai-triage
      matchers:
        - severity = "critical"
      continue: true
    # ... human routes follow
receivers:
  - name: ai-triage
    webhook_configs:
      - send_resolved: false
        url_file: /etc/alertmanager/secrets/<secret>/<key>
```
