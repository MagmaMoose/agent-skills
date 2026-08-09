#!/usr/bin/env bash
# k8s-harvest.sh - one read-only dump of a Kubernetes cluster, for audit agents to read from files.
#
# Why a harvest instead of live queries: an audit fans out over many agents. If each one runs its
# own kubectl, you get API load, rate limits, tunnel saturation, and - worse - agents that disagree
# because they sampled the cluster at different moments. Harvest once, point everyone at the files,
# and every finding is anchored to the same instant.
#
# Usage:
#   scripts/k8s-harvest.sh <kube-context> <output-dir> [--wide]
#
# Examples:
#   scripts/k8s-harvest.sh prod-cluster ./harvest/prod
#   scripts/k8s-harvest.sh staging ./harvest/staging --wide   # adds full describes, slower
#
# Read-only by construction: every command is get/describe/top/api-resources/version/raw-GET.
# It never applies, patches, deletes, scales, annotates, or reconciles anything.
#
# Missing CRDs are normal. A cluster without Flux, Longhorn, CNPG, Istio or Gateway API writes a
# file containing the "server doesn't have a resource type" error, which is itself evidence: the
# auditor learns what is absent without a second round trip.

set -uo pipefail   # deliberately NOT -e: one absent CRD must not abort the harvest

CTX="${1:-}"
OUT="${2:-}"
WIDE="${3:-}"

if [[ -z "$CTX" || -z "$OUT" ]]; then
  echo "usage: $0 <kube-context> <output-dir> [--wide]" >&2
  exit 2
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH" >&2
  exit 2
fi

mkdir -p "$OUT"
k() { kubectl --context "$CTX" "$@" 2>&1; }

echo "harvesting context=$CTX -> $OUT"
{
  echo "context: $CTX"
  echo "harvested_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kubectl: $(kubectl version --client -o json 2>/dev/null | tr -d '\n' | head -c 400)"
} > "$OUT/_harvest-meta.txt"

# --- cluster / control plane -------------------------------------------------
k version -o json                                                   > "$OUT/version.json"
k get nodes -o wide                                                 > "$OUT/nodes.txt"
k get nodes -o json                                                 > "$OUT/nodes.json"
k top nodes                                                         > "$OUT/top-nodes.txt"
k get --raw='/readyz?verbose'                                       > "$OUT/apiserver-readyz.txt"
k get --raw='/livez?verbose'                                        > "$OUT/apiserver-livez.txt"
k get componentstatuses                                             > "$OUT/componentstatuses.txt"
k get ns --show-labels                                              > "$OUT/namespaces.txt"
k api-resources -o wide                                             > "$OUT/api-resources.txt"
k get crd -o custom-columns=NAME:.metadata.name,GROUP:.spec.group,VERSIONS:.spec.versions[*].name \
                                                                    > "$OUT/crds.txt"
k get events -A --sort-by=.lastTimestamp                            > "$OUT/events-all.txt"
k get events -A --field-selector type=Warning --sort-by=.lastTimestamp \
                                                                    > "$OUT/events-warning.txt"
k get leases -n kube-system                                         > "$OUT/leases-kube-system.txt"

# Capacity vs allocatable per node, in one table. A control-plane node whose allocatable equals its
# capacity has no system-reserved/kube-reserved set, so the scheduler is being told the API server,
# scheduler, controller-manager and kubelet cost nothing. That is how a small control-plane node
# ends up admitting pods against headroom that does not exist and then hard-locking.
k get nodes -o custom-columns='NODE:.metadata.name,CPU_CAP:.status.capacity.cpu,CPU_ALLOC:.status.allocatable.cpu,MEM_CAP:.status.capacity.memory,MEM_ALLOC:.status.allocatable.memory,PODS_CAP:.status.capacity.pods' \
                                                                    > "$OUT/node-capacity-vs-allocatable.txt"

# Per-node requested/limits totals and conditions. `describe nodes` is the only built-in that sums
# requests per node, and the tail of each block carries MemoryPressure/DiskPressure/PIDPressure.
k describe nodes                                                    > "$OUT/nodes-describe.txt"

# --- workloads ---------------------------------------------------------------
k get pods -A -o wide                                               > "$OUT/pods.txt"
k get pods -A -o json                                               > "$OUT/pods.json"
k get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded \
                                                                    > "$OUT/pods-notrunning.txt"
k get deploy,sts,ds,rs,job,cronjob -A -o wide                       > "$OUT/controllers.txt"
k top pods -A --sort-by=memory                                      > "$OUT/top-pods-mem.txt"
k top pods -A --sort-by=cpu                                         > "$OUT/top-pods-cpu.txt"
k get pdb -A -o wide                                                > "$OUT/pdb.txt"
k get hpa -A                                                        > "$OUT/hpa.txt"
k get vpa -A                                                        > "$OUT/vpa.txt"
k get scaledobjects.keda.sh -A                                      > "$OUT/keda.txt"
k get priorityclasses                                               > "$OUT/priorityclasses.txt"
k get resourcequota,limitrange -A                                   > "$OUT/quota-limitrange.txt"
k get serviceaccounts -A                                            > "$OUT/serviceaccounts.txt"

# Restart counts and last-terminated reasons. An OOMKilled container writes NO application logs -
# it dies before flushing - so `lastState.terminated.reason` is often the only record that it
# happened at all. Sorting by restartCount surfaces the crash loops nobody reported.
k get pods -A -o json 2>/dev/null | \
  jq -r '.items[] | . as $p | .status.containerStatuses[]? |
    [$p.metadata.namespace, $p.metadata.name, .name, (.restartCount|tostring),
     (.state|keys[0]? // "-"), (.state.waiting.reason? // "-"),
     (.lastState.terminated.reason? // "-"), (.lastState.terminated.exitCode?|tostring // "-")] |
    @tsv' 2>/dev/null | sort -k4 -rn                                > "$OUT/container-restarts.tsv"

# The rendered nodeSelector of every workload. A placement value set in Helm values or a kustomize
# patch is only real once it reaches the pod template; charts silently discard per-component keys
# they do not have, and a global default loses to a non-empty per-component default. This file is
# the ground truth that a values file is not.
k get deploy,sts,ds -A -o json 2>/dev/null | \
  jq -r '.items[] | [.kind, .metadata.namespace, .metadata.name,
    (.spec.template.spec.nodeSelector // {} | tojson),
    (.spec.template.spec.priorityClassName // "-"),
    ((.spec.template.spec.tolerations // []) | length | tostring)] | @tsv' 2>/dev/null \
                                                                    > "$OUT/rendered-placement.tsv"

# Requests, limits and QoS per container. A limit equal to the measured working set is a deferred
# OOMKill, a missing request makes the pod BestEffort and the kubelet's first eviction victim, and
# a workload with no resources at all is invisible to the scheduler.
k get pods -A -o json 2>/dev/null | \
  jq -r '.items[] | . as $p | .spec.containers[] |
    [$p.metadata.namespace, $p.metadata.name, .name, ($p.status.qosClass // "-"),
     (.resources.requests.cpu // "-"), (.resources.requests.memory // "-"),
     (.resources.limits.cpu // "-"), (.resources.limits.memory // "-")] | @tsv' 2>/dev/null \
                                                                    > "$OUT/resources-qos.tsv"

# --- networking --------------------------------------------------------------
k get netpol -A                                                     > "$OUT/networkpolicies.txt"
k get svc -A -o wide                                                > "$OUT/services.txt"
k get endpoints -A                                                  > "$OUT/endpoints.txt"
k get endpointslices -A                                             > "$OUT/endpointslices.txt"
k get ingress -A -o wide                                            > "$OUT/ingress.txt"
k get ingressclass                                                  > "$OUT/ingressclasses.txt"
k get ingressroute,ingressroutetcp,middleware -A                    > "$OUT/traefik-crds.txt"
k get gateways.gateway.networking.k8s.io,httproutes,grpcroutes,referencegrants -A \
                                                                    > "$OUT/gateway-api.txt"
k get peerauthentication,authorizationpolicy,sidecar -A             > "$OUT/mesh-auth.txt"
k get gateway.networking.istio.io,virtualservice,destinationrule -A > "$OUT/mesh-routing.txt"
k get ciliumnetworkpolicies,ciliumclusterwidenetworkpolicies -A     > "$OUT/cilium-policies.txt"

# --- storage / data ----------------------------------------------------------
k get storageclass -o wide                                          > "$OUT/storageclasses.txt"
k get csidrivers                                                    > "$OUT/csidrivers.txt"
k get volumesnapshotclass,volumesnapshot -A                         > "$OUT/volumesnapshots.txt"
k get pv -o wide                                                    > "$OUT/pv.txt"
k get pvc -A -o wide                                                > "$OUT/pvc.txt"
k get nodes.longhorn.io -A -o wide                                  > "$OUT/longhorn-nodes.txt"
k get volumes.longhorn.io -A -o wide                                > "$OUT/longhorn-volumes.txt"
k get backuptargets.longhorn.io,recurringjobs.longhorn.io -A        > "$OUT/longhorn-backup.txt"
k get cluster.postgresql.cnpg.io -A                                 > "$OUT/cnpg-clusters.txt"
k get scheduledbackup.postgresql.cnpg.io,backup.postgresql.cnpg.io -A \
                                                                    > "$OUT/cnpg-backups.txt"
k get backups.velero.io,schedules.velero.io,restores.velero.io -A   > "$OUT/velero.txt"

# --- security / policy / identity --------------------------------------------
k get clusterpolicy,policy -A                                       > "$OUT/kyverno-policies.txt"
k get validatingadmissionpolicies,validatingadmissionpolicybindings > "$OUT/vap.txt"
k get mutatingadmissionpolicies,mutatingadmissionpolicybindings     > "$OUT/map.txt"
k get constrainttemplates,constraints -A                            > "$OUT/gatekeeper.txt"
k get validatingwebhookconfigurations -o custom-columns='NAME:.metadata.name,FAILUREPOLICY:.webhooks[*].failurePolicy,TIMEOUT:.webhooks[*].timeoutSeconds,SCOPE:.webhooks[*].rules[*].scope' \
                                                                    > "$OUT/validatingwebhooks.txt"
k get mutatingwebhookconfigurations -o custom-columns='NAME:.metadata.name,FAILUREPOLICY:.webhooks[*].failurePolicy,TIMEOUT:.webhooks[*].timeoutSeconds' \
                                                                    > "$OUT/mutatingwebhooks.txt"
k get clusterrolebindings -o json                                   > "$OUT/clusterrolebindings.json"
k get clusterrolebinding -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
                                                                    > "$OUT/clusterrolebindings.txt"
k get rolebindings -A -o wide                                       > "$OUT/rolebindings.txt"
k get certificate,certificaterequest -A -o wide                     > "$OUT/certificates.txt"
k get clusterissuer,issuer -A                                       > "$OUT/issuers.txt"
k get externalsecret,clusterexternalsecret,clustersecretstore,secretstore -A -o wide \
                                                                    > "$OUT/externalsecrets.txt"
k get sealedsecrets -A                                              > "$OUT/sealedsecrets.txt"
# Names and types only. Never harvest secret VALUES into a file an agent will read.
k get secrets -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp' \
                                                                    > "$OUT/secrets-inventory.txt"

# --- observability -----------------------------------------------------------
k get servicemonitors,podmonitors,probes -A                         > "$OUT/servicemonitors.txt"
k get prometheusrules -A                                            > "$OUT/prometheusrules.txt"
k get prometheus,alertmanager,alertmanagerconfig,thanosruler -A     > "$OUT/prom-operator.txt"
k get opentelemetrycollectors,instrumentations -A                   > "$OUT/otel.txt"
k get apiservices                                                   > "$OUT/apiservices.txt"

# --- GitOps ------------------------------------------------------------------
k get gitrepository,ocirepository,helmrepository,bucket -A          > "$OUT/flux-sources.txt"
k get kustomization -A                                              > "$OUT/flux-kustomizations.txt"
k get helmrelease -A                                                > "$OUT/flux-helmreleases.txt"
k get imagerepository,imagepolicy,imageupdateautomation -A          > "$OUT/flux-image-automation.txt"
k get applications,appprojects,applicationsets -A                   > "$OUT/argocd.txt"

# --- images ------------------------------------------------------------------
# Every running image, deduped. The digest-pinned ratio, the registry spread, and the count of
# floating tags all come out of this one file.
k get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null \
  | sort -u                                                         > "$OUT/images.txt"

# --- datastore pressure ------------------------------------------------------
# Object counts per kind. Unbounded accumulation of a short-lived kind is a classic way to bloat
# the datastore on a small control plane: a controller that produces ephemeral objects keeps
# producing them after the consumer that deletes them is switched off.
{
  for r in $(kubectl --context "$CTX" api-resources --verbs=list --namespaced -o name 2>/dev/null | sort -u); do
    n=$(kubectl --context "$CTX" get "$r" -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "${n:-0}" -gt 0 ]] && echo -e "${n}\t${r}"
  done
} 2>/dev/null | sort -rn                                            > "$OUT/object-counts.tsv"

# --- optional deep dive ------------------------------------------------------
if [[ "$WIDE" == "--wide" ]]; then
  k describe pods -A                                                > "$OUT/pods-describe.txt"
  k get all -A -o yaml                                              > "$OUT/all-resources.yaml"
fi

echo "DONE context=$CTX -> $OUT ($(ls -1 "$OUT" | wc -l | tr -d ' ') files)"
