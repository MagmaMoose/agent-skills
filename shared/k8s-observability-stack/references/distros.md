# Distributions

What differs between Kubernetes distributions, as far as this stack cares: which control-plane
components Prometheus can scrape, and where node-level certificates live.

## The rule

Every control-plane scrape target is either **scraped and up**, or **disabled together with the
alert rules that depend on it**. Never ship a target that is permanently down. A `KubeSchedulerDown`
that fires forever teaches everyone to ignore the alert channel, and the real alert that follows gets
ignored with it.

Always scraped, on every distribution: the API server (through the `kubernetes` Service), kubelet
and cAdvisor. CoreDNS is scraped where it runs as pods in the cluster.

The four that vary: kube-scheduler, kube-controller-manager, etcd and kube-proxy. In
kube-prometheus-stack each has a top-level block (`kubeScheduler`, `kubeControllerManager`,
`kubeEtcd`, `kubeProxy`) with `enabled`, and matching rule groups under `defaultRules.rules`
(`kubeSchedulerAlerting`, `kubeSchedulerRecording`, `kubeControllerManager`, `etcd`, `kubeProxy`).
Disabling a component means both.

## Summary

| Distribution | Scheduler, controller-manager | etcd | kube-proxy |
| --- | --- | --- | --- |
| k3s | Only with server flags, and then scrape one endpoint (below) | Only embedded etcd with `--etcd-expose-metrics=true` | Only with `--kube-proxy-arg=metrics-bind-address=0.0.0.0` |
| kubeadm and similar | Bound to 127.0.0.1 by default; rebind or disable | Metrics on 127.0.0.1:2381 by default; rebind or disable | 127.0.0.1:10249 by default; rebind or disable |
| EKS | Through the API server on Kubernetes 1.28+ (below); disable the chart's default jobs | Not scrapeable; disable | DaemonSet; check `metricsBindAddress` in the kube-proxy config |
| AKS | Not scrapeable by self-hosted Prometheus (Azure Monitor managed Prometheus only); disable | Same; disable | Absent with Azure CNI powered by Cilium; otherwise check its bind address |
| GKE | Not scrapeable in-cluster (Cloud Monitoring control plane metrics); disable | Not scrapeable; disable | Absent on Dataplane V2 (Cilium), the default for new Autopilot clusters; disable there |

Verify on the actual cluster: a flag, a ConfigMap, or the absence of a kube-proxy DaemonSet is
evidence. A distribution name is not.

## k3s

Every Kubernetes component runs inside the one k3s process. By default the scheduler and
controller-manager bind to loopback, etcd metrics listen on `127.0.0.1:2381`, and kube-proxy's
metrics on `127.0.0.1:10249`.

**If the server flags are not set,** disable all four components and their rule groups. That is the
common case, and the correct default.

**If the user wants control-plane metrics,** they need these k3s server flags (a node config change
and a k3s restart, which the output documents but does not perform):

```yaml
# /etc/rancher/k3s/config.yaml on server nodes
kube-controller-manager-arg:
  - bind-address=0.0.0.0
kube-scheduler-arg:
  - bind-address=0.0.0.0
kube-proxy-arg:
  - metrics-bind-address=0.0.0.0
etcd-expose-metrics: true      # embedded etcd only
```

Then the part that is k3s-specific: **the process has one metrics registry, so every component's
metrics endpoint serves the metrics of all components** (k3s documents this). Scraping the scheduler,
controller-manager and kube-proxy endpoints separately stores every series three times. Scrape one
endpoint per server node:

- Enable one component block (for example `kubeControllerManager`) with `endpoints:` set to the
  server node IPs, since there are no pods for the chart to select, and `jobNameOverride: k3s-server`.
- Leave the other component blocks disabled.
- The chart's `*Down` rules key on the per-component job names, so disable those rule groups and
  alert on `up{job="k3s-server"} == 0` instead.
- Exposing `0.0.0.0` puts these endpoints on the node network. NetworkPolicy does not cover host
  network ports, so restrict them with the node firewall.

Node certificates for the x509 exporter's DaemonSet on k3s: server certificates under
`/var/lib/rancher/k3s/server/tls/` (including `etcd/`), kubelet certificates under
`/var/lib/rancher/k3s/agent/`, and the admin kubeconfig at `/etc/rancher/k3s/k3s.yaml`. The
x509-certificate-exporter project ships a k3s example values file; start from it.

## kubeadm and similar self-managed distributions

The scheduler and controller-manager run as static pods bound to `127.0.0.1`, etcd serves metrics on
`127.0.0.1:2381`, and kube-proxy on `127.0.0.1:10249`. Either rebind them (the kubeadm
`ClusterConfiguration` `extraArgs` for `bind-address` and etcd's `listen-metrics-urls`, and
`metricsBindAddress` in the kube-proxy ConfigMap) or disable them. The same host-network exposure
warning applies.

Node certificates: `/etc/kubernetes/pki/` and the kubelet certificates under
`/var/lib/kubelet/pki/`.

For other self-managed distributions (RKE2, Talos, and so on), look up that distribution's own flags
for exposing control-plane metrics during the run rather than assuming the kubeadm or k3s answer.
OpenShift ships its own monitoring stack built on the same operators; stop and ask before deploying
a second one next to it.

## EKS

- On Kubernetes 1.28 and later, EKS exposes scheduler and controller-manager metrics through the API
  server at `/apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics` (scheduler) and
  `/apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics` (controller-manager). Prometheus needs
  RBAC `get` on `ksh/metrics` and `kcm/metrics` in the `metrics.eks.amazonaws.com` API group, and a
  scrape config that targets the `default/kubernetes` endpoints over HTTPS with those metrics paths.
  Disable the chart's `kubeScheduler` and `kubeControllerManager` blocks, which look for pods that do
  not exist, and add the scrape through `additionalScrapeConfigs` if the user wants these metrics.
- etcd is not scrapeable. Disable it. The etcd database size is available from CloudWatch.
- kube-proxy runs as a DaemonSet. Check `metricsBindAddress` in its config before enabling the
  target.

## AKS

- Control-plane metrics are only available through Azure Monitor managed Prometheus
  (`--enable-control-plane-metrics`), not to a self-hosted Prometheus. Disable the scheduler,
  controller-manager and etcd blocks and rules.
- kube-proxy does not exist with Azure CNI powered by Cilium. Otherwise check its bind address.

## GKE

- Control-plane metrics (API server, scheduler, controller-manager) go to Cloud Monitoring through
  Google Cloud Managed Service for Prometheus when control plane metrics are enabled. They are not
  scrapeable in-cluster. Disable the scheduler, controller-manager and etcd blocks and rules.
- On GKE Dataplane V2 (Cilium), Services are handled without kube-proxy. Disable kube-proxy there.
- Autopilot restricts DaemonSets and host access: node-exporter, node-problem-detector and the x509
  exporter's host-path DaemonSet may be rejected. Check what Autopilot allows before generating them.

## Managed control planes in general

- DaemonSets never reach managed control-plane nodes, because they are not in the cluster.
- The API server's own certificate is managed by the provider. The x509 exporter's host-path
  DaemonSet is only useful for kubelet certificates there, if at all.
