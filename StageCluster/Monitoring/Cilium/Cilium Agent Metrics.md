# Cilium Agent Metrics

## 1. Overview

Cilium Agent metrics provide visibility into the networking components running on each Kubernetes node.

Cilium is deployed as a DaemonSet, meaning one Cilium Agent Pod runs on every Linux node. Each Agent exposes Prometheus metrics through TCP port `9962`, using the `/metrics` HTTP endpoint.

In this Kubernetes cluster:

- Kubernetes version: `1.36.4`
- Cilium version: `1.20.2`
- Cilium namespace: `kube-system`
- Deployment type: DaemonSet
- Metrics port: `9962/TCP`
- Metrics endpoint: `/metrics`
- Metrics format: Prometheus

## 2. Cilium Agent Deployment

Cilium Agent is deployed as a DaemonSet named `cilium`.

This ensures that every eligible Linux node runs one Agent Pod.

Verify the DaemonSet:

```bash
kubectl get daemonset -n kube-system cilium
```

Expected result:

```text
NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
cilium   9         9         9       9            9
```

List the Agent Pods and their nodes:

```bash
kubectl get pods -n kube-system \
  -l k8s-app=cilium -o wide
```

The nine Cilium Agents run on:

| Node | Node IP |
|---|---|
| stage-masterf1 | 172.25.3.194 |
| stage-masterf2 | 172.25.3.195 |
| stage-masterf3 | 172.25.3.196 |
| stage-workerf1 | 172.25.3.197 |
| stage-workerf2 | 172.25.3.198 |
| stage-workerb1 | 172.25.9.114 |
| stage-workerb2 | 172.25.9.115 |
| stage-workerd1 | 172.25.25.18 |
| stage-workerd2 | 172.25.25.19 |

## 3. Enable Prometheus Metrics Through Helm

Cilium Agent metrics are enabled through the Cilium Helm configuration.

The relevant configuration is:

```yaml
prometheus:
  enabled: true
  port: 9962
  metricsService: true
```

Configuration details:

| Helm value | Purpose |
|---|---|
| `prometheus.enabled` | Enables the Cilium Agent metrics endpoint |
| `prometheus.port` | Defines the metrics listening port |
| `prometheus.metricsService` | Creates a Kubernetes Service for metrics discovery |

The metrics endpoint is exposed at:

```text
http://<agent-address>:9962/metrics
```

To inspect the currently applied Helm values:

```bash
helm get values cilium -n kube-system -a
```

To inspect the effective Cilium configuration:

```bash
kubectl get configmap cilium-config \
  -n kube-system -o yaml
```

Look for:

```yaml
prometheus-serve-addr: ":9962"
```

## 4. Kubernetes Metrics Service

A Service named `cilium-agent` exists in the `kube-system` namespace.

Its purpose is to expose the Cilium Agent metrics endpoints to Kubernetes service discovery.

The current Service configuration is:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cilium-agent
  namespace: kube-system
spec:
  clusterIP: None
  ports:
    - name: metrics
      port: 9962
      protocol: TCP
      targetPort: prometheus
  selector:
    k8s-app: cilium
  type: ClusterIP
```

### Service configuration details

| Setting | Description |
|---|---|
| `name` | `cilium-agent` |
| `namespace` | `kube-system` |
| `clusterIP: None` | Configures a headless Service |
| `port` | `9962` |
| `targetPort` | Container port named `prometheus` |
| `selector` | Selects Cilium Agent Pods |
| `type` | `ClusterIP` |

### Why use a headless Service?

A headless Service does not allocate a virtual ClusterIP.

Instead, Kubernetes publishes the individual endpoints associated with the Service.

This allows Prometheus Kubernetes endpoint discovery to identify individual Cilium Agent targets rather than relying on a single load-balanced Service address.

The intended endpoint structure is:

```text
cilium-agent Service
        |
        +-- Cilium Agent on stage-masterf1:9962
        +-- Cilium Agent on stage-masterf2:9962
        +-- Cilium Agent on stage-masterf3:9962
        +-- Cilium Agent on stage-workerf1:9962
        +-- Cilium Agent on stage-workerf2:9962
        +-- Cilium Agent on stage-workerb1:9962
        +-- Cilium Agent on stage-workerb2:9962
        +-- Cilium Agent on stage-workerd1:9962
        +-- Cilium Agent on stage-workerd2:9962
```

Verify the Service:

```bash
kubectl get svc -n kube-system cilium-agent -o yaml
```

Verify its endpoints:

```bash
kubectl get endpoints -n kube-system cilium-agent -o wide
```

Or inspect EndpointSlices:

```bash
kubectl get endpointslices -n kube-system \
  -l kubernetes.io/service-name=cilium-agent
```

## 5. Prometheus Scrape Configuration

Prometheus uses Kubernetes service discovery to discover Cilium Agent endpoints.

The scrape configuration is:

```yaml
- job_name: 'cilium-agent'
  kubernetes_sd_configs:
    - role: endpoints
      namespaces:
        names:
          - kube-system

  relabel_configs:
    - source_labels: [__meta_kubernetes_service_name]
      action: keep
      regex: cilium-agent

    - source_labels: [__meta_kubernetes_endpoint_port_name]
      action: keep
      regex: metrics
```

### How it works

1. Prometheus queries Kubernetes service discovery.
2. It discovers endpoints in the `kube-system` namespace.
3. The first relabel rule keeps only endpoints belonging to `cilium-agent`.
4. The second relabel rule keeps only the Service port named `metrics`.
5. Prometheus scrapes each discovered endpoint individually.

The resulting targets should correspond to the nine Cilium Agent instances.

The Prometheus Kubernetes discovery identity needs sufficient RBAC permissions to list and watch Services, Endpoints or EndpointSlices, depending on the discovery configuration and Prometheus version.

## 6. Metrics Validation

Metrics can be tested directly from a Kubernetes node.

Test the Agent on `stage-masterf1`:

```bash
curl -s http://172.25.3.194:9962/metrics | head -20
```

To display Cilium metrics only:

```bash
curl -s http://172.25.3.194:9962/metrics \
  | grep '^cilium_' | head -20
```

To test all nine node addresses:

```bash
for ip in \
  172.25.3.194 \
  172.25.3.195 \
  172.25.3.196 \
  172.25.3.197 \
  172.25.3.198 \
  172.25.9.114 \
  172.25.9.115 \
  172.25.25.18 \
  172.25.25.19
do
  echo "Checking $ip"

  curl -s --connect-timeout 3 \
    "http://${ip}:9962/metrics" \
    | grep -m 1 '^cilium_' || echo "No metrics response"
done
```

A successful response should contain Prometheus metric names beginning with `cilium_`.

## 7. Network Requirements

The metrics endpoint uses TCP port `9962`.

For an external Prometheus server to scrape each Cilium Agent directly, network connectivity must be allowed from the Prometheus server to the individual Agent endpoint addresses on port `9962`.

Required network access:

| Source | Destination | Protocol | Port | Purpose |
|---|---|---|---|---|
| External Prometheus | Kubernetes node/Agent endpoint IPs | TCP | 9962 | Scrape Cilium Agent metrics |

The network rules should restrict access to the Prometheus server's source IP.

The headless Service provides endpoint discovery; it does not make the endpoint addresses reachable from an external network.

If external Prometheus cannot reach the endpoint addresses, an alternative is to run a Prometheus scraper inside the cluster and forward the collected metrics to the external Prometheus system using `remote_write`.

## 8. Important Distinction Between Cilium Metrics

Cilium has separate metrics endpoints for different components.

| Component | Port | Purpose |
|---|---:|---|
| Cilium Agent | 9962 | Agent and Cilium networking metrics |
| Cilium Operator | 9963 | Operator metrics |
| Cilium Envoy | 9964 | Envoy proxy metrics |
| Hubble | 9965 | Network flow metrics |

These endpoints are independent. Enabling Cilium Agent metrics does not automatically enable Hubble flow metrics.

## 9. Useful Troubleshooting Commands

```bash
# Check Cilium DaemonSet
kubectl get ds -n kube-system cilium

# Check all Cilium Agent Pods
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# Check the metrics Service
kubectl get svc -n kube-system cilium-agent

# Check the Service endpoints
kubectl get endpoints -n kube-system cilium-agent -o wide

# Check EndpointSlices
kubectl get endpointslices -n kube-system \
  -l kubernetes.io/service-name=cilium-agent

# Check the metrics listening configuration
kubectl get configmap cilium-config -n kube-system -o yaml \
  | grep -i prometheus

# Test metrics endpoint
curl -s http://172.25.3.194:9962/metrics | head
```

## 10. Architecture Summary

Cilium Agent runs on every Linux node as a DaemonSet. Prometheus metrics are enabled through Helm and exposed on TCP port `9962`.

A headless Kubernetes Service named `cilium-agent` selects all Agent Pods and publishes their endpoints. Prometheus uses Kubernetes endpoint discovery to identify and scrape each Agent independently.

External Prometheus requires network connectivity to each discovered endpoint on TCP port `9962`.

This design provides per-node Cilium Agent metrics without requiring a separate metrics exporter on each node.