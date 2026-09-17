# Storage model

Object storage is the only durable tier. Every PersistentVolume in this stack is working state: a
write-ahead log, a cache, or scratch space. Losing one costs a restart, a cache warm-up or at most
the last few minutes of unflushed data. It never costs history, because history is in the bucket.

## The rule

**Never size a PV as if it holds history.** If the user asks for one (a 500Gi Prometheus volume for
90 days, a Loki volume "big enough for a month of logs"), flag it as an error: the retention they
want belongs in object storage and the compactor retention flags, and a history-sized PV is money
spent on a copy that gets deleted anyway. Then generate the working-state size.

## What each PV holds

| Component | Holds | Reference size | Sizing input | When it fills |
| --- | --- | --- | --- | --- |
| prometheus | WAL plus 6 to 12h of 2h blocks | 50Gi | Ingested samples per second, local retention | Ingestion stops; with the sidecar, blocks not yet uploaded are at risk |
| thanos-store | Index headers for the blocks it serves | 50Gi | Number and size of blocks in the bucket | Store cannot load new blocks; queries over those ranges return partial data |
| thanos-compactor | Scratch for the compaction group in progress | 100Gi | Largest compaction group, not bucket size | Compaction halts or retries forever; retention and downsampling stop |
| thanos-ruler | Rule results as local 2h blocks before upload | 10Gi | Number and cardinality of recording rules | Rule evaluation fails |
| alertmanager | Notification log and silences | 1Gi | Barely grows | Silences and dedup state lost on restart |
| loki-write | WAL and chunks not yet flushed | 10Gi | Ingest rate, flush interval | Pushes rejected; the WAL cannot replay after a crash |
| loki-backend | Compactor working directory, index gateway cache, ruler scratch | 10Gi | Index size per day | Compaction and retention stop |
| tempo | WAL, head blocks, metrics-generator WAL | 10Gi | Spans per second, block flush settings | Ingestion stops |
| grafana | Nothing. Database is external | none | | |
| memcached | Nothing. Memory only | none | | Evictions, lower hit rate |

## Sizing notes

### Prometheus

Disk for local blocks is roughly
`retention_seconds * samples_per_second * bytes_per_sample`, where `bytes_per_sample` is 1 to 2
after compression. Add the WAL, which holds about the last two to three hours at a higher cost per
sample. Measure the ingest rate on an existing install with
`rate(prometheus_tsdb_head_samples_appended_total[1h])`.

Keep `retentionSize` about 20% below the PV size so size-based retention acts before the disk is
full. Remember invariant 3: 6h is the floor, and retention is also how long the bucket can be
unreachable before unuploaded blocks are lost.

### Thanos compactor

The compactor downloads every source block of one compaction group, writes the output, then uploads
it. Size it for the largest group: about twice the size of the largest compacted block for one
external label set. With 2-week maximum compaction, that is two weeks of one Prometheus replica's
blocks, doubled, which matches Thanos's own worst case ("2 times 2 weeks" of smaller blocks) and its
rule of thumb of about 100GB for a medium bucket. Downsampling needs similar space for its input
block. A bucket of several terabytes can still need only 100Gi of scratch.

Retention flags default to `0d`, which means keep forever, and retention only runs when compaction
succeeds. Set `--retention.resolution-raw`, `--retention.resolution-5m` and
`--retention.resolution-1h` explicitly, and keep the 5m and 1h values above 10 days, because
downsampling to 1h needs that much 5m data first.

An undersized compactor does not fail loudly. It errors with "no space left on device", retries on
its next wait interval, and `thanos_compact_halted` can stay at 0 the whole time. That is why
`validation.md` checks that iterations actually complete.

### Thanos store

The store gateway keeps an index header for each block. It can rebuild them from the bucket, so an
`emptyDir` works if slow startup after a reschedule is acceptable. A PV makes restarts fast.

### Loki and Tempo

These PVs exist so a crashed pod can replay its WAL. Size for a few hours of ingest at peak, not for
retention. If a PV routinely runs above half full, flushes are failing or the ingest rate grew, and
the fix is upstream of the volume.

## Growing a volume later

StatefulSet `volumeClaimTemplates` are immutable. To grow a volume:

1. Confirm the StorageClass has `allowVolumeExpansion: true`. If not, the only path is a new PVC and
   a restart, which is acceptable here because the contents are working state.
2. Patch each PVC's `spec.resources.requests.storage`.
3. Delete the StatefulSet with `--cascade=orphan` so the pods keep running.
4. Apply the manifest with the new template size so the StatefulSet is recreated and adopts the
   pods.

Operators that own the StatefulSet (prometheus-operator for Prometheus, Alertmanager and Thanos
Ruler) document their own version of this procedure. Follow theirs, because the operator recreates
the StatefulSet itself.

## Storage class choice

- **Replicated block storage** (Ceph RBD, Longhorn and similar): pods can move to any node with
  their volume. Replication inside the storage layer duplicates what Loki, Tempo and the Prometheus
  pair already replicate, so a single storage replica is often enough for these volumes.
- **Zonal cloud disks** (AWS EBS, GCE persistent disks, zonal Azure disks): a pod can move with its
  volume only to another node **in the same zone**. With one node per zone they behave like
  node-pinned storage, and invariant 10's drain procedure applies. Use a StorageClass with
  `volumeBindingMode: WaitForFirstConsumer`, and spread replicas across zones with
  `topologySpreadConstraints` on `topology.kubernetes.io/zone` in addition to the hostname
  anti-affinity.
- **Node-pinned storage** (local-path, local PVs, LVM-backed CSI drivers): fastest and cheapest, but
  a pod cannot leave its node. Invariant 10 applies in full, and the output README must carry the
  drain procedure.
- Record in the output which class each PV uses and whether it supports expansion.
