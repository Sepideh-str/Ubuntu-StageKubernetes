# Hubble Metrics Monitoring

## 1. Overview

Hubble is the network observability component integrated into the Cilium Agent. It observes network traffic and provides visibility into network flows, DNS queries, HTTP requests, TCP connections, and dropped packets.

Hubble runs inside each Cilium Agent Pod. Since Cilium is deployed as a DaemonSet, each node has its own Hubble observer and metrics endpoint.

Hubble metrics are exposed on TCP port `9965`, using the `/metrics` endpoint.

## 2. Architecture

The monitoring architecture is:

```text
Kubernetes Cluster
│
├── stage-masterf1
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-masterf2
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-masterf3
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-workerf1
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-workerf2
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-workerb1
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-workerb2
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
├── stage-workerd1
│   └── Cilium Agent
│       └── Hubble Metrics :9965
│
└── stage-workerd2
    └── Cilium Agent
        └── Hubble Metrics :9965
```

Each Cilium Agent exposes its own Hubble metrics. Prometheus discovers and scrapes the individual endpoints.

**Important distinction:**

- Hubble runs inside the Cilium Agent.
- Hubble Relay is a separate Deployment used to aggregate and provide access to Hubble flow information.
- Prometheus scrapes the Hubble metrics endpoint exposed by each Cilium Agent, not Hubble Relay, for per-node Hubble metrics.

## 3. Enable Hubble Metrics

Hubble metrics are configured through the Cilium Helm chart.

Example values:

```yaml
hubble:
  enabled: true

  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http
```

The enabled metric categories determine which Hubble metrics are exposed.

Note:
- DNS metrics provide visibility into DNS queries.
- Drop metrics provide visibility into dropped traffic.
- TCP metrics provide TCP connection information.
- Flow metrics provide network flow information.
- ICMP metrics provide ICMP traffic information.
- HTTP metrics provide HTTP request visibility when L7 visibility is available and configured.

The exact metrics exposed depend on the enabled metric configuration.

## 4. Hubble Metrics Service

The Cilium Helm chart creates a Kubernetes Service for Hubble metrics when metrics are enabled.

Expected Service configuration:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hubble-metrics
  namespace: kube-system
spec:
  clusterIP: None
  ports:
    - name: hubble-metrics
      port: 9965
      protocol: TCP
      targetPort: hubble-metrics
  selector:
    k8s-app: cilium
  type: ClusterIP
```

The Service is headless (`clusterIP: None`) and selects Cilium Agent Pods.

This allows Kubernetes service discovery to identify the individual Agent endpoints instead of sending all scrape requests through one load-balanced Service IP.

A headless Service is the conventional Cilium chart design for discovering individual Hubble metrics endpoints.

## 5. Prometheus Scrape Configuration

Prometheus uses Kubernetes service discovery with the `endpoints` role.

Example:

```yaml
- job_name: 'hubble-metrics'
  kubernetes_sd_configs:
    - role: endpoints
      namespaces:
        names:
          - kube-system

  relabel_configs:
    - source_labels: [__meta_kubernetes_service_name]
      action: keep
      regex: hubble-metrics

    - source_labels: [__meta_kubernetes_endpoint_port_name]
      action: keep
      regex: hubble-metrics
```

### How it works

1. Prometheus discovers Services and their endpoints in the `kube-system` namespace.
2. The first relabel rule keeps only the `hubble-metrics` Service.
3. The second relabel rule keeps only the `hubble-metrics` port.
4. Prometheus discovers each Cilium Agent endpoint separately.
5. Prometheus scrapes each endpoint on port `9965`.

The resulting targets should correspond to the Hubble metrics endpoints on the nine Cilium Agent Pods.

## 6. Network Access Requirements

For an external Prometheus server to scrape Hubble metrics directly, network connectivity is required to the individual discovered endpoint IPs.

| Source | Destination | Protocol | Port | Purpose |
|---|---|---|---:|---|
| External Prometheus | Cilium Agent endpoints | TCP | 9965 | Hubble metrics scraping |

The network team should allow TCP `9965` from the external Prometheus server to all nine Kubernetes node/Agent endpoint IPs, subject to the actual endpoint addresses discovered by Kubernetes.

Kubernetes API access is also required for Kubernetes service discovery, with appropriate authentication and RBAC permissions.

**Important:** The `hubble-metrics` Service is internal to Kubernetes. External Prometheus must be able to reach the discovered endpoint IPs; access to the Service object alone does not provide network connectivity.

If external Prometheus cannot reach the Pod network, an in-cluster Prometheus can scrape Hubble metrics and forward them to the external Prometheus using `remote_write`.

## 7. Validation

### Check Hubble metrics configuration

```bash
helm get values cilium -n kube-system -a
```

Inspect the `hubble.metrics.enabled` section.

### Check the Hubble metrics Service

```bash
kubectl get svc -n kube-system hubble-metrics -o yaml
```

Verify:
- Service name: `hubble-metrics`
- Namespace: `kube-system`
- Port: `9965`
- Service selects Cilium Agent Pods.

### Check endpoints

```bash
kubectl get endpoints -n kube-system hubble-metrics -o wide
```

Or inspect EndpointSlices:

```bash
kubectl get endpointslices -n kube-system \
  -l kubernetes.io/service-name=hubble-metrics -o wide
```

You should see endpoints corresponding to the Cilium Agent Pods.

### Test metrics from inside the cluster

Run a temporary curl Pod:

```bash
kubectl run hubble-metrics-test \
  -n kube-system \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- sh
```

From inside the Pod:

```bash
curl -s http://hubble-metrics.kube-system.svc:9965/metrics | head
```

To test a particular Agent endpoint directly:

```bash
curl -s http://<AGENT-POD-IP>:9965/metrics | head
```

### Check for Hubble metrics

```bash
curl -s http://<AGENT-POD-IP>:9965/metrics | grep '^hubble_'
```

Metric names depend on the enabled metric categories.

## 8. Expected Result

After configuration:

- Each Cilium Agent exposes its own Hubble metrics endpoint.
- Kubernetes service discovery identifies the individual endpoints.
- Prometheus scrapes each endpoint independently.
- Hubble metrics provide network traffic and flow visibility across the Kubernetes nodes.

Hubble metrics complement the other Cilium monitoring jobs:

| Component | Deployment type | Metrics port | Monitoring purpose |
|---|---|---:|---|
| Cilium Agent | DaemonSet | 9962 | Cilium networking and agent health |
| Cilium Operator | Deployment | 9963 | Cluster-level Cilium management |
| Hubble | Integrated into Cilium Agent | 9965 | Network flows and traffic visibility |

