# Kubernetes platform audit workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and
relevant `README.md` files, plus any `COMMON_MISTAKES` / footgun log the repo keeps. Treat explicit
hard rules from the target repository as blockers: a propose-only policy, a "never touch production
without X" rule, a commit-trailer ban, or a documented access path all win over this file.

You are auditing a Kubernetes platform against a world-class bar. The goal is that the most senior
platform engineer available reads the result and is genuinely impressed by it: every criticism is
true, evidenced, and actionable, every strength is named rather than buried, and nothing important
was left unexamined.

The deliverable is not a list of everything that could theoretically be better. It is an honest,
ranked account of what this platform actually is right now, what is actively broken, what will
break next, what is already excellent, and the sequence in which to fix the rest.

## The one rule that matters most

**A repository audit and a live-cluster audit find different things. Do both.**

The repository describes intent. The cluster describes reality. They diverge constantly and the
divergence is where the severe findings live. A repo can be clean, reviewed, and fully GitOps-managed
while the running cluster has had no alert delivery for a week, because a manifest that merged
correctly references a secret that was never created.

If you only have repo access, say so explicitly in the deliverable and mark every finding as
repo-only. Do not let a clean repo imply a healthy cluster.

## Voice

The report and any issues you file are read by people, and often by people who built the thing you
are criticising. Write accordingly.

- Second person or plain declarative, present tense, active voice. State what is, then what to do.
- Lead each finding with the fact, not the feeling. "Alertmanager has been in `Init` for 5 days;
  no alert has been delivered in that window" beats "alerting appears to be in a concerning state".
- Never soften a critical finding into a suggestion, and never inflate a nit into a risk. A
  reviewer who catches you overstating once discounts everything else you wrote.
- Name what is genuinely good, specifically, and early. An audit that is all criticism reads as
  uncalibrated and gets dismissed as such.
- No blame, no speculation about who did what or why. "This was never wired up" not "somebody
  forgot to".
- Ban outright: "it's worth noting", "in today's landscape", "delve", "leverage", "utilize",
  "seamlessly", "robust"/"comprehensive"/"powerful" as filler, and any sentence that could be
  written about any cluster.
- No marketing, no robot emojis, no attribution footer of any kind.

## Rules of engagement

**Read-only by default.** Every state-changing operation is propose-only until the user explicitly
authorises it, and then only within the scope they set. That includes `kubectl apply/edit/patch/
delete/scale/annotate/cordon/drain`, `flux reconcile`/`suspend`, `helm upgrade`, Argo sync, secret
writes, image bumps, `terraform`/`tofu apply`, and any git history rewrite. `get`, `describe`,
`logs`, `top`, `api-resources`, and raw GETs are fine.

**Ground every finding three ways** where each applies:

1. **Live evidence** - the harvest file or the exact read-only command, with the output that proves
   it. Not "monitoring looks unhealthy" but "`kube-prometheus-stack` HelmRelease `Ready=False`,
   reason `context deadline exceeded`, for 5d6h".
2. **Repo evidence** - `path:line`. If you are claiming an absence, say where you looked to be sure
   it is absent. A grep that covered the whole tree is evidence; an assumption is not.
3. **A verified external source** - for anything about versions, EOL dates, deprecations, CVEs, or
   what current best practice is. Your training is stale by construction. Check, then cite what you
   checked.

**Absence of a control is a valid finding**, and often the most important one, but only when you
prove you looked. State the search.

**Never invent** a file path, a resource name, a version, or a config value. If you are unsure,
confirm it or leave it out. One fabricated `path:line` destroys the credibility of the whole
document.

**Classify every finding** so the reader knows what to do with it:

| Kind | Meaning |
| --- | --- |
| `new` | Nothing in the issue tracker or open PRs covers this |
| `confirms` | An existing issue covers it. Say whether the open PR actually closes it against live reality |
| `regression` | Was fixed or believed fixed, and live evidence shows otherwise |
| `falsely-claimed-fixed` | A doc, changelog, issue, or PR asserts this is done, and it is not |
| `false-alarm` | A prior audit or a colleague's claim that live evidence refutes. Say so plainly |

`falsely-claimed-fixed` is the highest-value category and the one that requires the most nerve.
A platform where the tracking documents disagree with the cluster is a platform where nobody can
trust any status, and that is a finding in its own right.

**Calibrate to the real constraints.** A four-node cluster run by one person is not a hyperscaler
fleet, and a critique that amounts to "hire an SRE team and buy managed everything" is worthless.
Steel-man the constraints. But do not let "small team" excuse a real single point of failure, a
data-durability gap, or a security hole - those are exactly what a hostile reviewer will find.
Note explicitly where the honest answer is **subtraction**: breadth that exceeds the operator's
capacity to run it is itself a root cause, not a strength.

---

## Phase 0 - Orient

Ten minutes here saves the whole engagement from re-deriving things that are already written down.

1. **Read prior audits, post-mortems, and the running cleanup or backlog doc.** Build on them, do
   not re-derive them. Note their date and treat every claim in them as a hypothesis to re-verify,
   not a fact. Checkbox state in a hand-maintained document is never evidence of anything.
2. **Read the agent docs** - `CLAUDE.md`, `AGENTS.md`, `.claude/`, any `COMMON_MISTAKES` file. These
   encode the hard rules and the traps somebody already paid for.
3. **Enumerate open issues and PRs** (`gh issue list`, `gh pr list`). The audit's job is to find what
   is *not* already tracked, so know what is. Build an issue to remediation-PR map early.
4. **Establish access and record it**: kube contexts, whether the API is reachable directly or only
   through a tunnel or bastion, secret-store access, cloud credentials, and which of these are
   read-only. Confirm `kubectl auth can-i --list` rather than assuming your permissions.
5. **Establish the shape of the platform** in one paragraph before you judge any of it: distribution
   and version, node count and roles, single or multi cluster, GitOps engine, ingress, CNI, storage,
   secrets, database, observability, identity. Everything downstream depends on getting this right.

Where remediation PRs already exist, the audit's value shifts. Half of it becomes: **does this PR
actually close the gap against live reality, or is it partial, cosmetic, or wrong?** Read the diff.
Do not take the title's word for it.

---

## Phase 1 - Harvest

Run one comprehensive read-only dump per cluster or environment, to files, before any fan-out.

```bash
scripts/k8s-harvest.sh <context> ./harvest/<env>
```

Resolve the script from `${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. If it
is not present, run the equivalent commands by hand and say so.

Two reasons this is not optional:

- **Load.** Twenty agents each running their own `kubectl` will saturate an API server, and through
  a tunnel or bastion it is worse.
- **Consistency.** Agents that sample at different moments produce findings that contradict each
  other, and you cannot tell which was right. One harvest means every finding is anchored to the
  same instant, and the timestamp goes in the report.

Harvest **every** cluster and environment, not just production. Cross-environment drift is one of
the highest-yield comparisons available: a staging cluster newer than production is an inverted
promotion gradient, meaning production upgrades were never rehearsed anywhere.

Missing CRDs are evidence, not errors. A file containing `the server doesn't have a resource type
"helmrelease"` tells you the cluster is not running Flux, which you needed to know anyway.

**Never harvest secret values.** Names, types, and ages only. The harvest files get read by agents
and often end up committed to an archive.

---

## Phase 2 - Verify the load-bearing items yourself

Do this before and during the fan-out, in the main thread. These are the checks that repeatedly
find the worst problems, and they are also the checks agents most often get subtly wrong. Every one
of them takes seconds.

### 2.1 Enumerate every pod that is not Running, and get the real reason

`kubectl get pods -A` and a glance at the `STATUS` column is not this check. The reason lives one
level down, in the container status.

```bash
kubectl get pods -A -o json | jq -r '
  .items[] | . as $p | .status.containerStatuses[]?
  | select(.ready == false)
  | [$p.metadata.namespace, $p.metadata.name, .name,
     (.state.waiting.reason // .state.terminated.reason // "-"),
     (.state.waiting.message // "-")] | @tsv'
```

**Bad answers:** `CreateContainerConfigError: secret "X" not found` (something upstream never
created it), `FailedMount`, `CrashLoopBackOff`, `ImagePullBackOff`, `Init:0/2` held for days,
`Pending` with `Insufficient memory/cpu`.

Then get the age of each. A pod that has been broken for hours is an incident. A pod that has been
broken for **weeks** is a monitoring finding, not a workload finding: the platform did not notice.

### 2.2 The self-concealing blindness check

Look for secrets that were never delivered, then ask which workloads mount them.

```bash
kubectl get externalsecret -A -o wide          # or sealedsecrets, or the equivalent
kubectl get externalsecret -A -o json | jq -r '
  .items[] | select(any(.status.conditions[]?; .type=="Ready" and .status=="False"))
  | [.metadata.namespace, .metadata.name,
     (.status.conditions[] | select(.type=="Ready") | .reason // "-")] | @tsv'
```

**The trap:** `grep -v SecretSynced` also filters out `SecretSyncedError`, because one is a
substring of the other. Match on the `READY` column or `status == "False"`, never on the reason
string.

**Why this check ranks so high:** a missing secret key silently kills whatever mounts it. If the
victims include the alerting stack - Alertmanager, the notification webhook, the dead-man's-switch
heartbeat, the dashboards - then the platform is blind *and cannot report its own blindness*.
Nothing fires, because the thing that fires is the thing that is down. Every other health signal
reads green. This single pattern has concealed a multi-day production outage, a three-week failed
reconcile, and a dead production service simultaneously.

Always finish the check by asking: **if this exact component were down, what would tell me?** If
the answer is "the component that is down", you have found it.

### 2.3 GitOps says Ready, the cluster says otherwise

```bash
kubectl get helmrelease,kustomization -A            # Flux
kubectl get applications -A                          # Argo
```

**Bad answers:** anything `Ready=False` for more than an hour, and especially anything `False` for
days or weeks with `context deadline exceeded` or an install-retries-exhausted message.

The subtler bad answer is `Ready=True` **while the workloads it owns are down**. A Kustomization
without `healthChecks`, or a HelmRelease without a health gate, reports success once the objects
are applied. Applied is not healthy. Cross-reference every `Ready=True` against 2.1 before you
believe it, and if the GitOps layer cannot tell the difference, that absence is itself the finding.

Check what the cluster reconciles *from*, too. A production environment tracking a feature branch,
or a `prune: true` reconciliation whose blast radius nobody has bounded, are both findings.

### 2.4 Does the node tell the truth about its own capacity

```bash
kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU_CAP:.status.capacity.cpu,CPU_ALLOC:.status.allocatable.cpu,MEM_CAP:.status.capacity.memory,MEM_ALLOC:.status.allocatable.memory'
kubectl describe nodes | grep -A8 'Allocated resources'
```

**Bad answer:** allocatable equals capacity on a node that also runs the control plane. The API
server, scheduler, controller-manager, datastore and kubelet live outside the pod cgroup hierarchy,
so with no `system-reserved` / `kube-reserved` / `eviction-hard` configured the scheduler is being
told they cost nothing. On a large node this wastes headroom. On a small control-plane node it is
how the node admits pods against gigabytes of headroom that do not exist, then exhausts memory and
hard-locks, needing a physical reset. Treat the node as the size it actually has, and check that
somebody has told the kubelet the same.

Also compare across nodes in the same cluster: kernel version drift, OS version, and container
runtime version. Drift between control-plane and worker nodes means there is no patch cadence.

### 2.5 Requests, limits, and the QoS consequences

```bash
kubectl get pods -A -o json | jq -r '.items[]
  | select(.status.qosClass=="BestEffort")
  | [.metadata.namespace, .metadata.name] | @tsv'
```

Three distinct findings hide here, and they are frequently confused with each other:

- **No resources at all** makes a pod `BestEffort`, which makes it the kubelet's *first* eviction
  and OOM target under node pressure. When the BestEffort workload is the database, the most
  critical stateful service on the node is the one that gets killed first. An OOM-killed database
  is an unclean shutdown, which is how instances come back wedged in WAL replay and need manual
  intervention.
- **A memory limit at or near the measured working set** is a deferred OOMKill, not a
  right-sizing. Anything inside roughly 10% of real usage will be killed eventually. This is worse
  for a JVM or any runtime that sizes its heap from the cgroup limit, because a tight limit makes
  it both more likely to exceed and less able to avoid it.
- **`request == limit`** (Guaranteed QoS) is only safe when the value sits above true peak. Setting
  it from a measured *average* turns a measurement into a hard cap.

**OOM forensics:** an OOMKilled container writes no logs at all. It dies before flushing anything,
so `kubectl logs` is empty and `kubectl logs --previous` is empty too. The only record is
`lastState.terminated` with `reason: OOMKilled` and `exitCode: 137`. Look there, always.

```bash
kubectl get pods -A -o json | jq -r '.items[] | . as $p | .status.containerStatuses[]?
  | select(.lastState.terminated.reason=="OOMKilled")
  | [$p.metadata.namespace,$p.metadata.name,.name,(.restartCount|tostring)] | @tsv'
```

**Measuring real usage** when the metrics API is unavailable:
`kubectl exec <pod> -- cat /sys/fs/cgroup/memory.current`. Better, when a metrics store exists,
take the **7-day peak** rather than an instantaneous reading: a `kubectl top` snapshot makes idle
workloads look over-provisioned when their peaks simply do not coincide, and "right-sizing" from
that snapshot causes the next outage.

**Raising a limit is free; raising a request is not.** Limits are not scheduler-reserved. On a node
that is already at 99% memory requested, raising a limit costs no capacity and fixes the OOMKill,
while raising the request leaves the pod unschedulable. When a node is genuinely full, say so:
sometimes the honest finding is "this node needs more RAM", and pretending it can be right-sized
away is how the same incident recurs.

**The rollout deadlock a full node produces.** On a two-replica Deployment, `maxUnavailable: 25%`
rounds down to zero, so the controller will not free an old pod until the new one is Ready, while
the new pod cannot schedule until that memory is freed. Both sides wait forever, and the Deployment
still reports its full replica count, so every dashboard says healthy. The tell is a surplus pod
`Pending` with `FailedScheduling: Insufficient memory` next to a Deployment that looks fine.

```bash
kubectl get pods -A --field-selector=status.phase=Pending -o wide
kubectl get replicasets -A -o json | jq -r '.items[]
  | select(.status.replicas > 0 and (.spec.replicas // 0) == 0)
  | [.metadata.namespace,.metadata.name,(.status.replicas|tostring)] | @tsv'
```

Breaking it means scaling the *old ReplicaSet* to zero, not deleting the pod, which its ReplicaSet
would simply recreate. Note this as an operational hazard wherever a node runs near its requested
capacity, because it turns any routine image bump into an incident.

### 2.6 Placement that was never actually applied

A `nodeSelector`, toleration, or affinity rule is only real once it reaches the **rendered pod
template**. Reading the values file or the kustomization proves nothing.

```bash
kubectl get deploy,sts,ds -A -o json | jq -r '.items[]
  | [.kind,.metadata.namespace,.metadata.name,
     (.spec.template.spec.nodeSelector // {} | tojson)] | @tsv'
```

**Bad answer:** an empty map, or the bare chart default, on a workload whose configuration clearly
intends a pin. Three ways this happens, all of which present identically to *no pin at all*:

- **A global value loses to a non-empty per-component default.** Many charts document
  `global.nodeSelector` while every component also carries its own default such as
  `{kubernetes.io/os: linux}`. A non-empty per-component value always wins, so the global setting
  never reaches a pod. Set it per component, and carry the chart's own default forward, because
  replacing the map replaces it wholesale.
- **A pod-level field set per container.** When a chart renders two containers into one pod, keys
  like `<component>.<container>.nodeSelector` do not exist, and the value is silently discarded.
- **A kustomize `patches:` target that matches nothing fails silently.** Change a workload's kind
  or name and every patch still naming the old one is orphaned. `kustomize build` neither warns
  nor errors; it renders the unpatched manifest. The symptom is a pod that suddenly requests what
  the base file says instead of what the patch said, with nothing in the diff to explain it.

The check is one command, and the rule is: verify by rendering (`helm template` with the real
values, `kustomize build`) and diffing the pod spec, never by reading the file that was supposed
to set it.

**Node label durability.** Labels applied imperatively live only in the datastore. They survive
reboots but not the Node object being recreated by a rebuild, re-join, or delete. Anything pinned
to such a label goes `Pending` at that moment, and if the GitOps controllers are among them, the
cluster cannot reconcile its own fix. Note also that the kubelet is forbidden from self-registering
labels in the `node-role.kubernetes.io/*` and reserved `kubernetes.io` namespaces, so those cannot
be made durable through the kubelet's own registration flags; a custom prefix can.

### 2.7 Objects that exist but are inert

The most flattering thing a platform can have is a control that is present and does nothing. Check
each one for teeth:

| Object | Inert when |
| --- | --- |
| Admission policy | Mode is `Audit`/`warn` rather than `Enforce`, or it matches no resources |
| Admission webhook | `failurePolicy: Ignore`, or its backing pods are down |
| NetworkPolicy | It exists in three namespaces and nowhere else, so there is no default-deny |
| Pod Security Admission | Labels on one namespace only, or `warn`/`audit` without `enforce` |
| PodDisruptionBudget | Selects zero pods, or permits zero voluntary disruptions |
| ServiceMonitor | Its selector matches no Service, so nothing is being scraped |
| Alert rule | Routed to a receiver that is a placeholder, or swallowed by a null route |
| Backup schedule | Its label selector matches no workload, so it backs up nothing |
| Image policy | Verification is not enforced at admission, so signing is ceremony |

```bash
kubectl get pdb -A -o json | jq -r '.items[]
  | [.metadata.namespace,.metadata.name,
     (.status.expectedPods|tostring),(.status.disruptionsAllowed|tostring)] | @tsv'
```

**PDBs deserve special care because they fail in both directions.** `minAvailable: 1` against a
single replica permits zero voluntary disruptions and therefore **blocks every node drain** - which
collides head-on with patching, and turns a routine upgrade into an incident. Meanwhile a PDB that
selects zero pods protects nothing while looking like protection. Note that some operator-generated
PDBs select a single pod deliberately, so that draining forces a failover; do not "fix" those.

### 2.8 Prove an alert can actually be delivered, end to end

Every layer of an alerting stack can be healthy while nothing reaches a human. Walk the whole path
rather than checking that the pods are Running.

```bash
kubectl get prometheusrules -A -o json | jq -r '.items[].spec.groups[].rules[]? | select(.alert) | .alert' | wc -l
kubectl -n <monitoring-ns> get secret <receiver-secret> -o json | jq -r '.data | keys[]'
kubectl -n <monitoring-ns> logs <alertmanager-pod> | tail -50
```

**Bad answers, each of which reads green from outside:**

- The receiver's URL or token is a **placeholder** that was never replaced. Alerts fire, delivery
  fails, and the failure is only visible in a log nobody reads.
- The **root route is a null receiver** and only specific severities are re-routed out of it, so an
  entire tier of alerts, usually the warning tier that carries crashloops, stuck rollouts and
  missing replicas, is silently swallowed by design.
- There is exactly **one delivery channel**, with no pager or escalation, so a channel outage is
  itself undetectable and self-concealing.
- The **dead-man's-switch** rule exists but nothing external watches for its absence, which means it
  proves nothing.

The finding to write is not "alerting is configured". It is whether a firing alert has been
observed to arrive, and if not, that nobody can currently say it would.

### 2.9 An IaC pin that no longer matches live

Read every version, size, and image pin in the infrastructure code against what the provider
actually reports. This check costs minutes and prevents the worst class of outcome, because some
attributes force **replacement** rather than update.

**Bad answer:** a pinned value the provider no longer offers, on a resource where changing that
attribute destroys and recreates it, with no deletion protection set. A plan against that pin does
not fail. It proposes destroying a live database and creating an empty replacement, and it looks
like an ordinary diff. The risk is dormant only while nothing can run the plan; the moment CI gains
access to that path, it is armed.

Check deletion protection and lifecycle rules on every stateful resource at the same time, and note
any leaf whose plan cannot currently be run, because that is where drift accumulates unseen.

### 2.10 Backups, and whether a restore has ever been proven

```bash
kubectl get backuptargets.longhorn.io,recurringjobs.longhorn.io -A
kubectl get schedules.velero.io,backups.velero.io -A
kubectl get scheduledbackup.postgresql.cnpg.io,backup.postgresql.cnpg.io -A
kubectl get volumesnapshotclass,volumesnapshot -A
```

**Bad answers, in descending order of severity:** no backup target configured at all; a target
configured but `available: false`; schedules whose selector matches nothing; a database backup with
no cluster-object or PV backup beside it; every copy landing in one cloud account or one tenant;
no immutability or versioning on the destination bucket; shared-key rather than identity auth; and
above all, **no restore that anybody has ever run**.

An unrehearsed backup is a hypothesis. The finding to write is not "backups exist" but "the RTO is
unknown because no restore has been timed". Ask for the written RTO and RPO. If there is no
document, that is the finding.

Watch for the mirror job that quietly stopped: check the age of the newest object in the
destination, not the existence of the job.

### 2.11 Version currency, from what is actually running

Read the live chart and image versions, not the ones in the repo, then verify EOL dates against a
current source.

```bash
kubectl get helmrelease -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CHART:.spec.chart.spec.chart,VERSION:.status.history[0].chartVersion'
sort -u harvest/*/images.txt
```

Then look for the **root cause rather than the symptoms**. When several components are all EOL at
once, the finding is almost never "these five components are old". It is that the dependency bot's
scope does not cover the manifests: an update tool configured for one directory or one file type,
leaving every chart pin and image tag invisible to it. That is a one-file fix that closes the
entire class, and it is a far better finding than five separate version bumps.

Also count the **digest-pinned ratio** and the **registry spread** from `images.txt`. Floating tags
plus a rate-limited public registry is both a supply-chain and an availability finding.

### 2.12 Who is actually cluster-admin

```bash
kubectl get clusterrolebindings -o json | jq -r '.items[]
  | select(.roleRef.name=="cluster-admin")
  | [.metadata.name, (.subjects//[] | map(.kind+":"+.name) | join(","))] | @tsv'
```

**Bad answers:** long-lived ServiceAccount token Secrets with cluster-admin, human users bound
directly rather than through a group, groups that do not resolve to anyone (so the binding is
inert and the only working admin is a break-glass account), and any impersonation path with no API
audit logging behind it - impersonation without audit destroys attribution entirely.

### 2.13 Admission and controller self-DoS

```bash
kubectl get validatingwebhookconfigurations -o custom-columns='NAME:.metadata.name,FAILURE:.webhooks[*].failurePolicy,TIMEOUT:.webhooks[*].timeoutSeconds'
```

**Bad answer:** many `failurePolicy: Fail` webhooks backed by single-replica controllers. Fail-closed
is the right default for a policy engine, but fail-closed plus a single pod means one controller
restart wedges admission cluster-wide, and recovery requires deleting the webhook config by hand.
Check replica counts and PDBs for every webhook backend, and check whether the policy engine
excludes its own namespace.

Related, and easy to miss: **where the policy engine runs**. A controller that writes a report
object per matched resource is a continuous write stream to the datastore. Pinning that controller
onto the same node that hosts the datastore turns policy coverage into control-plane load, and the
symptom is the API server failing its own readiness check under TLS handshake timeouts.

Then check for **unbounded accumulation**, which is the sibling defect. Producer and consumer of
short-lived objects are usually separate controllers; disable the consumer and nothing ever deletes
what the producer keeps making. Objects named for a lifetime of seconds accumulate for days.

```bash
for r in $(kubectl api-resources --verbs=list --namespaced -o name | sort -u); do
  n=$(kubectl get "$r" -A --no-headers 2>/dev/null | wc -l); [ "$n" -gt 0 ] && echo "$n $r";
done | sort -rn | head -20
```

Anything in the thousands that is not pods, events, or replicasets deserves an explanation.

### 2.14 Slow starts and the probes that kill them

A container that needs minutes to become ready, and has only a `livenessProbe`, will be killed
mid-startup whenever `initialDelaySeconds + failureThreshold x periodSeconds` is shorter than its
real startup. For anything replaying a write-ahead log, that failure is **unbounded**: each killed
replay leaves a larger log, so the next start takes longer and is killed sooner in relative terms.

The correct primitive is a `startupProbe`, which suspends liveness and readiness until it first
succeeds. Check for slow-starting stateful components with no `startupProbe` defined.

### 2.15 Storage locality and cross-site writes

Where replicated storage spans sites or availability zones, check where each volume's replicas
actually are relative to the pod using it.

**Bad answer:** the pod on one site with all replicas on another, so every write crosses the link
synchronously. The symptom is not "slow" - it is startup probes that can never finish, and restart
counts in the hundreds. Check the storage layer's data-locality setting, and check it on the
**StorageClass**, because a StorageClass parameter overrides the global default for every volume
provisioned through it. A global setting can read as enabled cluster-wide while every volume runs
with it disabled.

### 2.16 Cross-environment drift

Diff the harvests. Every difference between staging and production is either a deliberate decision
or a defect, and the platform should be able to say which.

```bash
diff <(cut -d' ' -f1 harvest/staging/namespaces.txt | sort) \
     <(cut -d' ' -f1 harvest/prod/namespaces.txt | sort)
diff harvest/staging/kyverno-policies.txt harvest/prod/kyverno-policies.txt
```

**Bad answers:** production on an older Kubernetes version than staging (an inverted promotion
gradient - production upgrades were never rehearsed), policies present in one and not the other,
RBAC tiers missing in production, a security stack wired into staging only, and any resource whose
existence differs with no explanation in the repo.

### 2.17 Merge-ordering hazards among open PRs

When a backlog is being remediated by many parallel PRs, some merge orders cause outages. This
section is often the single most useful page in the report, and nothing else produces it.

Read the open diffs and look for pairs where order matters:

- A PR that prunes the only working admin path must not merge before the PR that fixes the
  replacement identity path.
- A PR that ships backups or snapshots off-site must not merge before the PR that enables
  encryption at rest, or you have just exported plaintext.
- A PR that enforces a policy must not merge before the PRs that make every workload compliant.
- A PR that raises requests must not merge onto a node that is already at capacity.

Write them as an explicit ordered list with the reason.

---

## Phase 3 - Fan out

Once the load-bearing facts are verified, parallelise for breadth. The pattern is **find, then
adversarially verify, then criticise for completeness**. One agent per dimension, a second agent
that tries to refute the first, and a final pass that asks what everyone missed.

### The shared ground prompt

Every agent gets the same preamble. This is what separates a useful fan-out from a pile of
plausible text:

- **The primary sources, in order**: the harvest files first, then the repo with `path:line`, then
  the issue-to-PR map. Name the exact paths.
- **A one-paragraph description of the platform** so critiques are calibrated rather than generic,
  including the real constraints (team size, private or managed infrastructure, regulatory context).
- **Cite live evidence and repo evidence for every finding.** No hand-waving.
- **Web-verify anything about versions, EOL, deprecations, or standards**, and say what was verified.
- **Assess each relevant open PR against live reality** by reading the diff, and judge whether it
  fully closes the gap, partially closes it, or is cosmetic or wrong.
- **Classify each finding** with the taxonomy above.
- **Read-only commands only. Never mutate.** Prefer harvest files.
- **Stay in your dimension**; another agent covers the rest.
- **The bar is world-class, but every criticism must be true and actionable.** No theatre.

### Dimensions

Roughly a dozen, each narrow enough that an agent can be exhaustive within it. Scope is deliberately
wider than security:

1. **Control plane and topology** - distribution and version, datastore health and quorum, node
   fleet and sizing, version skew across clusters, kernel and OS drift, upgrade strategy, snapshot
   configuration, reserved resources, single-site placement, API reachability and bastion SPOFs.
2. **Workload and pod security** - Pod Security Admission coverage, `securityContext` across all
   workloads (`runAsNonRoot`, dropped capabilities, seccomp, read-only root filesystem, privileged,
   host namespaces, hostPath), `automountServiceAccountToken`, admission-policy completeness.
3. **Network** - default-deny coverage, CNI enforcement, mesh configuration and whether it has
   authorization policies at all (encryption without segmentation is a half-measure), egress
   control, tenant isolation, ingress surface, edge and perimeter rules.
4. **Secrets** - provider architecture and its own HA, sync health, rotation cadence, whether
   anything alerts when a sync fails, encryption at rest in the datastore, secret sprawl, committed
   credentials in git and in git *history*.
5. **GitOps and CI** - reconciliation health, health-gating, prune blast radius, manifest validation
   before merge, promotion and approval flow, which ref each environment tracks, drift between git
   and live, and the supply chain of the CI itself.
6. **Storage and data** - database HA and failover, replica counts, backup coverage and restore
   proof, RTO/RPO, StorageClass choices for stateful data, capacity and fill, encryption at rest,
   PITR, data locality.
7. **Observability** - whether alerts can actually be delivered end to end, whether the alerting can
   observe its own health, dead-man's-switch, log shipping, retention, SLOs and error budgets,
   dashboards that match reality, synthetic external probes, and the null-route trap where a root
   route silently swallows an entire severity tier.
8. **Infrastructure as code** - state backend, locking, drift detection, plan-in-CI, credentials in
   state or in the repo, module quality, and any pin that would destroy live data on the next apply.
9. **Supply chain** - build provenance, SBOM, signing and admission-time verification, digest
   pinning ratio, base image hygiene, registry sourcing, and whether scanning results reach anyone.
10. **Identity and RBAC** - the full authentication chain and every component's support status,
    least privilege, group claims that actually resolve, standing credentials, API audit logging.
11. **Resilience, DR and capacity** - single points of failure, PDB correctness in both directions,
    autoscaling, N-1 node headroom, noisy neighbours, failure-domain spread, disaster runbooks and
    whether any of them have been rehearsed.
12. **Governance and compliance** - the baselines that actually apply, control mapping, data
    residency and sovereignty, egress of data to third parties including AI services, log PII and
    retention, audit evidence, and right-to-erasure implications.
13. **Version currency and future-proofing** - EOL components, deprecated APIs in the current
    release line, the dependency-bot scope gap, upgrade cadence, and CRD version drift.

Adjust the list to the platform. A managed cluster on a cloud provider moves weight from "control
plane" to "cloud IAM and network"; a single-tenant internal cluster moves it from "tenant isolation"
to "blast radius and operator ergonomics".

### Structured output

Force each agent to return structured findings rather than prose. Minimum fields:

```
title, severity (critical|high|medium|low), kind (new|confirms|regression|
falsely-claimed-fixed|false-alarm), live_evidence, repo_evidence, coverage
(which issue/PR, and does it fully close this against live?), best_practice
(what you verified, and where), recommendation, better_tool (or why the current
choice is right)
```

The verification pass adds `verdict` (`CONFIRMED` / `PLAUSIBLE` / `REFUTED` / `SEVERITY-ADJUSTED`)
and `verify_note`. Its instruction is to **try to refute**, not to review: re-open the harvest, the
repo and the PR diffs, correct severities, catch hallucinated paths and misread state, drop
anything not grounded, and add the obvious gap the first pass missed.

### The two passes that produce the best findings

**The completeness critic** reads every verified finding and asks one question: *what did the whole
audit still miss?* This consistently produces the highest-order truths, because it is the only agent
looking across dimensions. Prompt it explicitly with the cross-cutting candidates: DNS and PKI
single points of failure, certificate and CA expiry automation, bastion HA, restore proof,
chaos and game-days, N-1 capacity, admission webhook self-DoS, time sync, log PII and lawful
egress, secret rotation cadence, the CI's own supply chain, whether the update bot covers the
GitOps engine itself, a measured hardening benchmark score, cross-cluster drift, whether the open
PRs are themselves correct and mergeable, and whether anything is over-engineered for the size of
the team that has to run it.

**The tool and method alternatives pass** answers "could I have chosen better?" with a verdict per
choice: **REPLACE** (with the migration cost and risk), **FIX-IN-PLACE**, or **VINDICATE**. The
vindications matter as much as the replacements: naming the choices that are already right stops
them being re-litigated forever, and a review that only ever recommends change is not a review.
This pass must be web-sourced, because the correct answer changes year to year, and it should be
willing to correct a *previous* audit's claim.

---

## Phase 4 - Synthesise the deliverable

The main thread writes this, not an agent. By this point you have been living in the data and the
agents have not.

Structure, in order:

0. **The one thing to read first.** If something is broken right now, it goes here in three lines,
   above everything else. If nothing is, say that plainly - it is a real result.
1. **Maturity scorecard** - a row per dimension, rated against what is *running*, not what is
   committed. Include the harvest timestamp.
2. **What is genuinely world-class.** Lead with these, specifically. This is what makes the rest
   land.
3. **Active incidents** - things broken now, with how long they have been broken, and what the
   duration implies about the monitoring.
4. **Critical findings**, deduped, each with real coverage against live reality.
5. **High findings**, grouped by theme rather than listed flat.
6. **Merge-ordering hazards**, if there is an open remediation backlog.
7. **Tool and method verdicts** - replace, fix in place, vindicate.
8. **Meta and human factors** - bus factor, standing credentials, personal-account dependencies,
   over-engineering relative to capacity. These are frequently the most severe findings in the
   document and the most uncomfortable to write. Write them anyway.
9. **Coverage map** - what is already tracked by an issue or PR, versus what is genuinely uncovered.
   The uncovered list is the candidate set for new tickets.
10. **Sequenced roadmap** - P0 to P3, ordered by what unblocks what, not by severity alone.

Then, if you acted during the session, an **actions taken** addendum saying exactly what changed.

Two rules for the document itself: **no silent truncation** (if you capped a list, say what was cut
and why), and **every count reconciles** (if the scorecard says 17 criticals, seventeen appear).

---

## Phase 5 - Act, within authorisation

Nothing in this phase happens without the user asking for it.

**Log the uncovered gaps as issues.** Write them in the owner's voice, not the auditor's:
first-person, forward-looking, matter-of-fact. No reference to an audit or review, no finger-
pointing, no severity theatre. Each one gets the problem in a sentence or two, an **Approach**, and
a **Done when** that is objectively checkable. Assign and label them.

The reason for the voice rule is practical: issues outlive the audit. An issue that reads "the
audit found that you failed to..." ages badly and gets closed unread. One that reads "I'd like to
turn on encryption at rest so a stray snapshot isn't a plaintext secret dump" gets worked on.

**Open safe, reversible PRs** for the one-file wins - one change per PR, following the repository's
review workflow and commit conventions. Check for a commit-trailer ban before you commit.

**Everything state-changing stays a proposal**: secret writes, `apply`, reconcile, image bumps,
`tofu apply`, history rewrites. If the user authorises one with constraints, respect the constraints
exactly and confirm the result afterwards.

**Do not disturb in-progress work.** To add files to a repository that is on another branch with
uncommitted changes, use a `git worktree` off the main branch rather than switching their tree.

**On a GitOps cluster, a live edit is temporary.** Anything patched directly is reverted at the next
reconcile, typically within minutes, which produces a fix that appears to work and then silently
undoes itself. If an authorised live change has to happen before the git change can land, suspend
the owning Kustomization or Application first and record that it needs resuming, or the suspension
becomes its own outage. The durable change is always the one in git.

**Confirm the result of anything you were authorised to change**, in the same session, with the same
read-only checks that found the problem. An unverified fix is an unverified claim.

---

## Named patterns to look for, and to name in the report

Naming a pattern is worth more than describing an instance, because the reader recognises the next
one themselves.

- **Self-concealing blindness** - the alerting is down because of the same failure it would have
  alerted on. Every health signal reads green. The fix is an out-of-band signal plus alerts on the
  health of the alerting *inputs*, and soft-mounting so observability pods start even when their
  secret is absent.
- **Repo-green, cluster-red** - "Applied" and "Ready" are not workload health unless something
  health-gates the pods.
- **Falsely-claimed-fixed** - the tracking document, changelog, or PR title asserts a fix that live
  evidence refutes. Corrodes trust in every other status in the system.
- **Version-currency root cause** - many EOL components at once is one dependency-bot scope gap,
  not many independent oversights.
- **Inverted promotion gradient** - a lower environment behind production, so nothing was ever
  rehearsed before it shipped.
- **Inert control** - the policy, PDB, ServiceMonitor, netpol, or backup schedule that exists and
  matches nothing.
- **A setting that never rendered** - values-file placement, patches orphaned by a kind change,
  global keys beaten by per-component defaults. Presents identically to no setting at all.
- **Deferred OOMKill** - a limit set from a measurement rather than above a peak.
- **Rollout deadlock** - `maxUnavailable` rounding to zero on a full node, so the new pod cannot
  schedule until the old one frees memory and the old one is not freed until the new one is Ready.
  The Deployment still reports its full replica count, so it looks healthy.
- **Producer without consumer** - disabling the controller that deletes short-lived objects while
  leaving the one that creates them, trading a bounded write stream for unbounded accumulation.
- **Single-tenant funnel** - every backup copy, or all DNS and all TLS issuance, depending on one
  account, one token, or one vendor plan.
- **Over-engineering for a bus factor of one** - breadth that exceeds the operator's capacity to run
  it is itself the root cause of "a lot of it is broken". The senior move is subtraction.
- **Merge-ordering hazard** - a correct PR that causes an outage because of when it lands.

---

## How audits themselves go wrong

Every one of these has happened. Guard against them explicitly.

- **Trusting a subagent's finding without opening the evidence.** Agents produce confident,
  well-formatted, wrong findings. Verify anything load-bearing yourself before it reaches the
  report.
- **A grep that hides what it is looking for.** Excluding a healthy status string also excludes the
  error string that contains it as a substring. Filter on structured status fields, not on text.
- **Reading a values file and concluding a setting is active.** Render it.
- **An instantaneous metric read as a working set.** Use a multi-day peak; a snapshot makes idle
  workloads look over-provisioned and produces "right-sizing" that causes the next outage.
- **Trusting a checkbox.** Hand-maintained status in a document is a claim to verify, never
  evidence.
- **Counting objects instead of assessing them.** "47 NetworkPolicies" says nothing; "no namespace
  has a default-deny" says everything.
- **Auditing the repo and reporting on the cluster**, or the reverse. Say which you looked at.
- **Severity inflation.** Everything critical means nothing is.
- **Stopping at the first plausible root cause.** The unclean shutdown was a symptom; the missing
  resource request was the cause; the absent alert on it was the reason nobody knew.
- **Recommending a migration that cannot run.** Check the prerequisites of your own recommendation
  against the actual nodes before you write it: kernel features, architecture, console access, and
  a way back in if it fails. A CNI or datastore migration on a cluster with no out-of-band console
  and no backups is not a recommendation, it is a hazard.
- **Silent truncation.** "Top 10 findings" without saying what was cut reads as "that is all of
  them".

---

## Currency: re-verify at run time

Anything below is time-sensitive and must be re-checked against a current source during the run.
Web-verify before asserting any of it in a deliverable.

- The Kubernetes versions currently in support, and which are EOL today.
- API deprecations and removals landing in the current and next release lines.
- The status of admission control: policy-engine CRD deprecations, and how much of the equivalent
  functionality is now native and GA in the API server.
- Current hardening guidance and benchmark versions, and what a measured score looks like.
- EOL dates for every component in the stack: ingress, mesh, CNI, storage, database operator,
  secrets operator, GitOps controllers, observability stack.
- Supply-chain expectations: signing, attestation formats, SBOM formats, and what admission-time
  verification currently requires.
- Ingress and gateway API status, and whether the mesh in use is still maintained.
- Backup tooling status and snapshot API maturity.
- Secrets: operator API versions and migration paths, and the current encryption-at-rest story.

Say in the report what you verified and when. A version claim with no source is worse than no
version claim.

---

## Definition of done

- Both the repository and the live cluster were examined, or the report states plainly which was
  not available and marks its findings accordingly.
- A harvest exists for every cluster and environment, with a timestamp, and every finding cites it.
- Every load-bearing claim in the report was verified first-hand, not taken from an agent.
- Every finding has live evidence, repo evidence where applicable, a classification, a severity, and
  a recommendation that names the specific change.
- Every version, EOL, and best-practice claim cites something checked during this run.
- Strengths are named specifically and appear before the criticism.
- Counts reconcile, nothing was silently truncated, and every capped list says what was cut.
- Merge-ordering hazards are listed if there is an open remediation backlog.
- No state-changing operation was performed without explicit authorisation, and anything that was
  authorised is recorded in an actions-taken section with its verification.
- No secret values appear anywhere in the harvest, the report, or any issue.
