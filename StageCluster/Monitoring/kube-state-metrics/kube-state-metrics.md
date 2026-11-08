# kube-state-metrics

## 1. Overview

kube-state-metrics (KSM) collects the current state of Kubernetes objects and exposes that information as Prometheus metrics.

It communicates with the Kubernetes API Server, watches Kubernetes resources, and exposes their state through an HTTP metrics endpoint.

Examples of collected metrics:

| Metric | Description |
|---|---|
| `kube_node_info` | Information about Kubernetes nodes |
| `kube_node_status_condition` | Node conditions and readiness |
| `kube_pod_info` | Information about pods |
| `kube_pod_status_phase` | Pod lifecycle status |
| `kube_deployment_status_replicas_available` | Available Deployment replicas |
| `kube_daemonset_status_number_ready` | Ready DaemonSet pods |
| `kube_statefulset_status_replicas_ready` | Ready StatefulSet replicas |
| `kube_persistentvolume_status_phase` | PersistentVolume status |
| `kube_persistentvolumeclaim_status_phase` | PersistentVolumeClaim status |

KSM reports Kubernetes object state. It does not directly collect CPU, memory, disk, or network usage. Those metrics come from other monitoring components.

## 2. Architecture

KSM runs as a Kubernetes Deployment, not a DaemonSet.

The current implementation uses one replica scheduled on a frontend node.

```text
Kubernetes API Server
        |
        | List / Watch Kubernetes objects
        |
kube-state-metrics Deployment
        |
        | HTTP /metrics
        |
kube-state-metrics Service
        |
        | Port 8080
        |
Prometheus
```

The KSM Deployment collects cluster-wide object information. It does not need one Pod per Kubernetes node.

## 3. Helm wrapper chart

The implementation uses a Helm wrapper chart so that the upstream kube-state-metrics chart can be maintained through the platform's GitOps repository.

Directory structure:

```text
kube-state-metrics/
├── Chart.yaml
└── values.yaml
```

### Chart.yaml

```yaml
apiVersion: v2
name: kube-state-metrics-wrapper
description: Helm wrapper for kube-state-metrics
type: application
version: 1.0.0

dependencies:
  - name: kube-state-metrics
    version: "8.8.0"
    repository: https://repository.crouseco.com/repository/prometheus-community-proxy/
```

Explanation:

| Setting | Description |
|---|---|
| `apiVersion: v2` | Uses the Helm 3 chart format |
| `name` | Name of the wrapper chart |
| `description` | Describes the chart's purpose |
| `type: application` | Identifies this as an application chart |
| `version` | Version of the wrapper chart |
| `dependencies` | Defines the upstream chart used by the wrapper |
| `version: 8.8.0` | Pins the kube-state-metrics Helm chart version |
| `repository` | Internal Helm repository proxy |

The wrapper chart lets us maintain our configuration separately from the upstream chart.

### values.yaml

```yaml
kube-state-metrics:
  replicas: 1

  image:
    registry: repository.crouseco.com
    repository: k8s-proxy/kube-state-metrics/kube-state-metrics
    tag: v2.20.0
    pullPolicy: IfNotPresent

  service:
    type: ClusterIP
    port: 8080

  rbac:
    create: true
    useClusterRole: true

  serviceAccount:
    create: true

  prometheus:
    monitor:
      enabled: false

  selfMonitor:
    enabled: false

  nodeSelector:
    zone: frontend
```

### 3.1 Replicas

```yaml
replicas: 1
```

Runs one KSM replica.

One instance is sufficient for the current implementation. It watches Kubernetes resources across the cluster, not just resources on the node where it runs.

If high availability is required later, replicas and the chart's supported sharding configuration should be reviewed together. Simply adding replicas without considering duplicate metrics can cause duplicate time series.

### 3.2 Image

```yaml
image:
  registry: repository.crouseco.com
  repository: k8s-proxy/kube-state-metrics/kube-state-metrics
  tag: v2.20.0
  pullPolicy: IfNotPresent
```

The image is retrieved through the internal container registry.

- `registry`: Internal registry hostname.
- `repository`: Image repository path.
- `tag`: kube-state-metrics application version.
- `pullPolicy`: Kubernetes uses a cached image when available.

There are two separate versions here:

- Helm chart version: `8.8.0`
- kube-state-metrics application version: `v2.20.0`

They are not the same version.

### 3.3 Service

```yaml
service:
  type: ClusterIP
  port: 8080
```

Creates an internal Kubernetes Service.

- `ClusterIP` provides an internal virtual IP.
- `8080` is the KSM metrics endpoint.
- Prometheus accesses the metrics through the Service or its discovered endpoint.

The Service is not exposed directly outside the cluster.

**Why ClusterIP?**

KSM is an internal monitoring component. It does not need to be exposed through a public or externally accessible Service by default.

Do not change it to NodePort just because Prometheus is outside the cluster. First determine how external Prometheus reaches the target.

### 3.4 RBAC

```yaml
rbac:
  create: true
  useClusterRole: true
```

KSM needs permission to read Kubernetes resources.

`create: true` tells Helm to create the required RBAC resources.

`useClusterRole: true` allows KSM to use cluster-scoped permissions rather than being restricted to a single namespace.

This is important because KSM collects information about resources across the Kubernetes cluster.

The permissions are read-oriented, typically `list` and `watch` on the resources enabled by the chart's collectors.

### 3.5 ServiceAccount

```yaml
serviceAccount:
  create: true
```

Creates a dedicated Kubernetes ServiceAccount for KSM.

The Deployment uses this identity when communicating with the Kubernetes API Server.

The ServiceAccount and RBAC configuration work together to provide the permissions KSM needs.

### 3.6 Prometheus ServiceMonitor

```yaml
prometheus:
  monitor:
    enabled: false
```

Disables creation of a Prometheus Operator ServiceMonitor.

This is appropriate because Prometheus is configured with its own `kubernetes_sd_configs` scrape job.

A ServiceMonitor is only needed when using Prometheus Operator discovery through that resource.

Disabling this setting does not disable the `/metrics` endpoint.

### 3.7 Self-monitoring

```yaml
selfMonitor:
  enabled: false
```

Disables the chart's optional self-monitoring endpoint configuration.

KSM has its main Kubernetes object metrics endpoint on port `8080`. It can also expose its own process and telemetry metrics, normally on port `8081`.

For the current implementation, only the main Kubernetes object metrics endpoint is required.

If we later want to monitor KSM's own process metrics, we can enable self-monitoring and configure a separate Prometheus scrape job.

### 3.8 Node selector

```yaml
nodeSelector:
  zone: frontend
```

Schedules the KSM Pod only on nodes with this label:

```text
zone=frontend
```

In the current cluster, this places KSM on an eligible frontend worker.

The node selector controls where the KSM Pod runs. It does not restrict which Kubernetes nodes or namespaces KSM monitors.

## 4. Service and network design

### ClusterIP versus Node IP

For this implementation, use a ClusterIP Service.

| Address type | Purpose |
|---|---|
| Pod IP | Actual address of the KSM Pod |
| ClusterIP | Internal virtual IP of the KSM Service |
| Node IP | Address of the Kubernetes node |
| NodePort | Port exposed on node IPs and forwarded to the Service |

The distinction matters when Prometheus runs outside Kubernetes.

A ClusterIP is normally reachable only from inside the cluster. External Prometheus cannot automatically access it.

### How Kubernetes endpoint discovery works

The Prometheus job uses:

```yaml
kubernetes_sd_configs:
  - role: endpoints
```

Kubernetes service discovery obtains the Service's endpoint addresses and ports.

For KSM, the discovered target is normally the Pod IP and metrics port:

```text
<KSM-POD-IP>:8080
```

It is not necessarily:

```text
<KSM-CLUSTER-IP>:8080
```

Therefore, external Prometheus needs network access to the KSM Pod IP and port `8080`.

It also needs access to the Kubernetes API Server and the appropriate RBAC permissions for Kubernetes service discovery.

### Recommended collection architecture

The primary monitoring system is the external Prometheus.

There are two possible network designs:

**Option A: External Prometheus scrapes KSM directly**

Use this if the external Prometheus server can reach the KSM Pod IP and port `8080`.

```text
External Prometheus
        |
        | Kubernetes API access for discovery
        |
Kubernetes API Server

External Prometheus
        |
        | TCP 8080 to KSM Pod IP
        |
KSM Pod
```

In this case, keep the KSM Service as ClusterIP. No NodePort is needed.

**Option B: In-cluster Prometheus scrapes KSM**

Use this if external Prometheus cannot reach the Pod network.

```text
KSM Pod
   |
   | ClusterIP / Service discovery
   |
In-cluster Prometheus
   |
   | Remote Write
   |
External Prometheus
```

In this design, in-cluster Prometheus scrapes KSM internally and sends the collected data to external Prometheus using remote_write.

This avoids exposing the KSM endpoint to the external network.

### Which option should we use?

For the current architecture, external Prometheus remains the primary monitoring system.

Prefer direct external scraping if routing and security allow access to the KSM Pod IP. If the Pod network is not reachable from the external Prometheus server, use in-cluster scraping with remote_write or a deliberately designed internal exposure mechanism.

Do not expose KSM publicly. If a NodePort or internal load balancer is required, restrict access to the external Prometheus source IP.

## 5. Prometheus scrape configuration

The current scrape job:

```yaml
- job_name: 'kube-state-metrics'
  kubernetes_sd_configs:
    - role: endpoints
      namespaces:
        names:
          - monitoring

  relabel_configs:
    - source_labels: [__meta_kubernetes_service_name]
      action: keep
      regex: kube-state-metrics

    - source_labels: [__meta_kubernetes_endpoint_port]
      action: keep
      regex: "8080"
```

Explanation:

| Setting | Description |
|---|---|
| `job_name` | Name of the Prometheus scrape job |
| `role: endpoints` | Discovers Kubernetes Service endpoints |
| `namespaces.names` | Limits discovery to the monitoring namespace |
| `__meta_kubernetes_service_name` | Service name discovered by Prometheus |
| `action: keep` | Keeps only matching targets |
| `regex: kube-state-metrics` | Selects the KSM Service |
| `__meta_kubernetes_endpoint_port` | Endpoint port discovered by Prometheus |
| `regex: "8080"` | Keeps only the main KSM metrics endpoint |

The port filter prevents Prometheus from accidentally scraping another port exposed by the same Service.

## 6. Implementation and validation

### 6.1 Update Helm dependencies

From the wrapper chart directory:

```bash
helm dependency update .
```

This downloads the chart dependency using the configured repository.

You can inspect the downloaded dependencies with:

```bash
helm dependency list .
```

### 6.2 Validate the chart

```bash
helm lint .
```

Render the manifests to verify the final configuration:

```bash
helm template kube-state-metrics . -n monitoring
```

### 6.3 Check the Deployment

```bash
kubectl get deployment -n monitoring kube-state-metrics -o wide
```

Check that the Pod is running:

```bash
kubectl get pods -n monitoring -o wide
```

Check its node placement:

```bash
kubectl get pods -n monitoring -o wide -l app.kubernetes.io/name=kube-state-metrics
```

Confirm the selected node has the expected label:

```bash
kubectl get nodes -L zone
```

### 6.4 Check the Service

```bash
kubectl get svc -n monitoring kube-state-metrics -o wide
```

Inspect the Service configuration:

```bash
kubectl get svc -n monitoring kube-state-metrics -o yaml
```

Expected configuration:

- Service type: `ClusterIP`
- Metrics port: `8080`

### 6.5 Check endpoints

```bash
kubectl get endpoints -n monitoring kube-state-metrics -o wide
```

Or, if using EndpointSlices:

```bash
kubectl get endpointslices -n monitoring \
  -l kubernetes.io/service-name=kube-state-metrics
```

Confirm that an endpoint address and port `8080` are present.

### 6.6 Test the metrics endpoint from inside Kubernetes

```bash
kubectl run ksm-test \
  -n monitoring \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- curl -s http://kube-state-metrics:8080/metrics
```

Check specific metrics:

```bash
kubectl run ksm-test \
  -n monitoring \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- sh -c 'curl -s http://kube-state-metrics:8080/metrics | grep -E "^kube_(node|pod|deployment|daemonset)_" | head -20'
```

### 6.7 Test the endpoint from external Prometheus

If external Prometheus has network access to the KSM Pod IP, test it directly:

```bash
curl -v http://<KSM-POD-IP>:8080/metrics
```

If this connection fails but the in-cluster test works, investigate routing and firewall access to the Pod CIDR.

### 6.8 Check Prometheus targets

In Prometheus, open:

```text
/api/v1/targets?state=active
```

Find the `kube-state-metrics` job.

Expected result:

```text
job: kube-state-metrics
endpoint: <KSM-POD-IP>:8080
state: UP
```

Check the following metrics in Prometheus:

```promql
kube_node_info
```

```promql
kube_pod_info
```

```promql
kube_deployment_status_replicas_available
```

```promql
kube_daemonset_status_number_ready
```

## 7. Network requirements

For direct external scraping, the following access is required:

| Source | Destination | Protocol | Port | Purpose |
|---|---|---|---|---|
| External Prometheus | Kubernetes API Server | TCP | 7443 | Kubernetes service discovery, using the configured API endpoint |
| External Prometheus | KSM Pod IP | TCP | 8080 | Scrape Kubernetes object metrics |

The API Server port above assumes the external Prometheus uses the configured Kubernetes API VIP on port `7443`.

The KSM endpoint must be reachable through the cluster's Pod network. Confirm the actual Pod CIDR and network routing before submitting the firewall request.

Do not request port `8081` for this implementation because self-monitoring is disabled.

Restrict access to the metrics endpoint to the authorized Prometheus source.

## 8. Final design decisions

| Item | Configuration |
|---|---|
| Component | kube-state-metrics |
| Application version | v2.20.0 |
| Helm chart version | 8.8.0 |
| Kubernetes workload | Deployment |
| Replicas | 1 |
| Namespace | monitoring |
| Node placement | `zone=frontend` |
| Service type | ClusterIP |
| Metrics port | 8080 |
| ServiceAccount | Created by Helm |
| RBAC | ClusterRole |
| ServiceMonitor | Disabled |
| Self-monitoring | Disabled |
| Primary monitoring system | External Prometheus |
| Alternative collection | In-cluster Prometheus with remote_write |

The important distinction is that **ClusterIP is the correct internal Service type, but it does not make KSM reachable from external Prometheus**. Direct external scraping requires Pod IP connectivity, or another explicitly configured network exposure. 