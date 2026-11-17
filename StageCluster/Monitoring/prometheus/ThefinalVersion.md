# Prometheus Metrics Collection

## 1. Overview

Prometheus is deployed inside the Kubernetes cluster and collects metrics from Kubernetes nodes and cluster components.

The monitoring configuration uses Kubernetes service discovery to find metric endpoints automatically. This means Prometheus does not need a manually maintained list of node IP addresses or Pod IP addresses.

The following components are monitored:

| Job | Component | Metrics Port | Number of Targets |
|---|---|---:|---:|
| `node-exporter` | Kubernetes node operating systems | 9100 | 9 |
| `kube-state-metrics` | Kubernetes API object states | 8080 and 8081 | 2 discovered targets |
| `cilium-agent` | Cilium networking agents | 9962 | 9 |
| `cilium-operator` | Cilium operator | 9963 | 2 |
| `hubble-metrics` | Cilium network observability | 9965 | 9 |

The target counts above reflect the current cluster discovery results. The kube-state-metrics job currently discovers two ports for its Service.

## 2. Prometheus Deployment Configuration

### Image

Prometheus uses the internally hosted image:

- Repository: `repository.crouseco.com/quay-proxy/prometheus/prometheus`
- Version: `v3.16.0`

### Deployment

Prometheus runs with one replica and is scheduled specifically on:

`stage-workerf1`

This is configured using:

```yaml
replicaCount: 1

nodeSelector:
  kubernetes.io/hostname: stage-workerf1
```

Prometheus therefore runs as a single instance on the frontend worker node.

### Storage and Retention

Prometheus uses an existing PersistentVolumeClaim:

```yaml
persistentVolume:
  enabled: true
  existingClaim: prometheus-pvc
  mountPath: /data
  storageClass: "-"
```

The PVC provides persistent storage for Prometheus time-series data.

Data retention is configured as:

```yaml
retention: "2d"
retentionSize: "12GB"
```

This means Prometheus retains data for up to two days, subject to the configured storage-size limit of 12 GB.

### Scrape and Evaluation Intervals

```yaml
global:
  scrape_interval: 30s
  scrape_timeout: 10s
  evaluation_interval: 30s
```

| Setting | Value | Description |
|---|---:|---|
| `scrape_interval` | 30 seconds | Prometheus collects metrics from each target every 30 seconds. |
| `scrape_timeout` | 10 seconds | A scrape must complete within 10 seconds. |
| `evaluation_interval` | 30 seconds | Prometheus evaluates configured recording and alerting rules every 30 seconds. |

For example, if a target is successfully scraped at 10:00:00, Prometheus will normally attempt the next scrape at approximately 10:00:30.

## 3. Kubernetes Service Discovery

All five scrape jobs use:

```yaml
kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names:
        - monitoring
```

or:

```yaml
kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names:
        - kube-system
```

The `role: endpoints` setting tells Prometheus to discover endpoint addresses and ports from Kubernetes Services.

Prometheus uses the Kubernetes API to discover the Services and their associated endpoints.

The discovery process is:

1. Prometheus queries the Kubernetes API for endpoint information in the configured namespace.
2. Kubernetes returns the endpoint addresses and associated ports.
3. Prometheus creates candidate scrape targets from those endpoints.
4. Relabeling rules filter the candidates to retain only the intended Service and port.
5. Prometheus scrapes the remaining targets using HTTP and the `/metrics` path by default.

This approach allows Prometheus to discover new endpoints automatically when Pods are added, removed, or rescheduled.

### Why use endpoint discovery?

A Kubernetes Service can represent one or multiple backend Pods.

For example, the Node Exporter Service is headless and exposes the endpoint of each Node Exporter Pod. Prometheus therefore discovers all nine Node Exporter instances rather than scraping only one address.

Similarly, the Cilium Agent and Hubble Metrics Services expose an endpoint for each Kubernetes node.

### Relabeling

Each job uses `relabel_configs` to filter discovered endpoints.

For example:

```yaml
- source_labels: [__meta_kubernetes_service_name]
  action: keep
  regex: node-exporter
```

This keeps only endpoints belonging to the `node-exporter` Service.

Another example:

```yaml
- source_labels: [__meta_kubernetes_endpoint_port_name]
  action: keep
  regex: metrics
```

This keeps only endpoints whose Kubernetes Service port is named `metrics`.

The port name is used instead of the numeric port metadata because the numeric endpoint port label was empty in the observed discovery results.

### Node Label

Each job also contains:

```yaml
- source_labels: [__meta_kubernetes_pod_node_name]
  target_label: node
```

This copies the Kubernetes node name associated with the endpoint into a Prometheus label named `node`.

For example:

```text
instance="10.0.3.3:9100"
node="stage-workerf1"
job="node-exporter"
```

This is useful because the `instance` label identifies the scrape endpoint, while the `node` label identifies the Kubernetes node associated with that endpoint.

It allows metrics to be grouped and filtered by Kubernetes node in PromQL and Grafana.

## 4. Node Exporter

### Purpose

Node Exporter collects operating-system and hardware-level metrics from Kubernetes nodes.

It runs as a DaemonSet, meaning Kubernetes schedules one Node Exporter Pod on every eligible node.

In this cluster, there are nine nodes and nine Node Exporter Pods.

### Service and Endpoint

The Node Exporter Service is located in the `monitoring` namespace.

It is a headless Service exposing the port:

```text
metrics: 9100
```

Because it is headless, Kubernetes publishes the individual Pod endpoints rather than providing a single ClusterIP for load balancing.

Prometheus discovers the Pod IPs through Kubernetes endpoint discovery.

Example:

```text
10.0.3.3:9100
10.0.0.78:9100
10.0.2.7:9100
```

These addresses represent individual Node Exporter Pods.

### Metrics Collected

Node Exporter provides operating-system metrics, including:

- CPU utilization and CPU time.
- Memory usage and availability.
- Filesystem capacity and utilization.
- Disk I/O statistics.
- Network interface statistics.
- System load.
- System uptime.

Example metric names:

```text
node_cpu_seconds_total
node_memory_MemAvailable_bytes
node_memory_MemTotal_bytes
node_filesystem_size_bytes
node_filesystem_avail_bytes
node_disk_read_bytes_total
node_network_receive_bytes_total
node_load1
```

### Target Identification

The `node` label identifies which Kubernetes node each Node Exporter endpoint belongs to.

For example:

```text
job="node-exporter"
instance="10.0.3.3:9100"
node="stage-workerf1"
```

This allows Grafana dashboards to display operating-system metrics separately for each Kubernetes node.

## 5. kube-state-metrics

### Purpose

kube-state-metrics collects metrics about the state of Kubernetes objects.

It communicates with the Kubernetes API and converts Kubernetes object information into Prometheus metrics.

Unlike Node Exporter, it does not collect operating-system or hardware metrics.

### Service and Endpoint

The Service is located in the `monitoring` namespace.

Prometheus discovers its endpoints through Kubernetes endpoint discovery.

The current discovery results show two targets:

```text
10.0.3.249:8080
10.0.3.249:8081
```

Both targets are currently UP.

The job filters by Service name:

```yaml
- source_labels: [__meta_kubernetes_service_name]
  action: keep
  regex: kube-state-metrics
```

Unlike the other jobs, it does not currently filter by endpoint port name.

### Metrics Collected

kube-state-metrics provides information about Kubernetes objects, including:

- Pods and their status.
- Deployments and replica availability.
- StatefulSets and DaemonSets.
- Nodes and their conditions.
- Kubernetes namespaces.
- PersistentVolumeClaims and PersistentVolumes.
- Resource requests and limits.
- Job and CronJob status.

Example metric names:

```text
kube_pod_info
kube_pod_status_phase
kube_pod_container_status_restarts_total
kube_deployment_status_replicas
kube_deployment_status_replicas_available
kube_node_status_condition
kube_persistentvolumeclaim_status_phase
```

These metrics help monitor the state of Kubernetes resources.

For example, Node Exporter can tell you how much memory is available on a node, while kube-state-metrics can tell you whether a Pod is running or waiting.

## 6. Cilium Agent

### Purpose

Cilium Agent is responsible for implementing and managing networking on Kubernetes nodes using eBPF.

Cilium runs as a DaemonSet, meaning there is normally one Cilium Agent Pod on each Kubernetes node.

The agent provides metrics about Cilium's networking operations and internal activity.

### Service and Endpoint

The Service is located in the `kube-system` namespace.

Its metrics port is:

```text
metrics: 9962
```

The Service is headless and exposes the individual node endpoints.

The discovered addresses in this cluster are node IP addresses:

```text
172.25.3.194:9962
172.25.3.195:9962
172.25.3.196:9962
172.25.3.197:9962
172.25.3.198:9962
172.25.9.114:9962
172.25.9.115:9962
172.25.25.18:9962
172.25.25.19:9962
```

The agent's metrics endpoint is exposed on the node network, so Prometheus scrapes the node IP rather than using the Cilium Pod IP.

### Metrics Collected

Cilium Agent metrics provide information about:

- Cilium endpoint status.
- eBPF operations.
- Network policy processing.
- Datapath activity.
- API interactions.
- Agent health and internal operations.
- Errors and dropped packets, where applicable.

Example metric families include:

```text
cilium_endpoint_state
cilium_drop_count_total
cilium_forward_count_total
cilium_policy
```

The exact metrics available depend on the enabled Cilium metrics configuration.

### Node Identification

The following relabeling rule:

```yaml
- source_labels: [__meta_kubernetes_pod_node_name]
  target_label: node
```

adds the Kubernetes node name to each discovered endpoint.

For example:

```text
job="cilium-agent"
instance="172.25.3.194:9962"
node="stage-masterf1"
```

This makes it possible to identify which node each Cilium Agent metrics endpoint belongs to.

## 7. Cilium Operator

### Purpose

Cilium Operator performs cluster-level Cilium management tasks.

Unlike Cilium Agent, which runs on every node, Cilium Operator runs as a Deployment with a limited number of replicas.

In this cluster, there are two operator replicas scheduled on the frontend worker nodes.

### Service and Endpoint

The Service is located in the `kube-system` namespace.

Its metrics port is:

```text
metrics: 9963
```

The current discovered endpoints are:

```text
172.25.3.197:9963
172.25.3.198:9963
```

Prometheus discovers both replicas through the Kubernetes Service endpoints.

### Metrics Collected

Cilium Operator metrics provide information about cluster-level Cilium operations, including:

- Operator health.
- Controller activity.
- Reconciliation operations.
- Errors and failures.
- Cilium resource management.

Example metric families include:

```text
cilium_operator_controllers
cilium_operator_process_cpu_seconds_total
cilium_operator_process_resident_memory_bytes
```

The exact metric families depend on the Cilium version and enabled metrics.

### Why are there only two targets?

Cilium Operator is a Deployment, not a DaemonSet.

Therefore, Prometheus discovers the two running replicas rather than one target per Kubernetes node.

This is expected behavior.

## 8. Hubble Metrics

### Purpose

Hubble is Cilium's network observability component.

It provides visibility into network activity and communication between Kubernetes workloads.

Hubble Metrics exposes Prometheus metrics about network flows and related networking activity.

### Service and Endpoint

The Service is located in the `kube-system` namespace.

Its metrics port is:

```text
hubble-metrics: 9965
```

The Service exposes one endpoint per Kubernetes node through the Hubble Metrics endpoint on each Cilium Agent.

The current discovered addresses are node IPs:

```text
172.25.3.194:9965
172.25.3.195:9965
172.25.3.196:9965
172.25.3.197:9965
172.25.3.198:9965
172.25.9.114:9965
172.25.9.115:9965
172.25.25.18:9965
172.25.25.19:9965
```

### Metrics Collected

Hubble Metrics can provide information about:

- Network flows.
- TCP activity.
- HTTP requests and responses.
- DNS requests and responses.
- Network policy verdicts.
- Dropped and forwarded traffic.

The actual metric families depend on the Hubble metrics configuration enabled in Cilium.

For example, the enabled metrics configuration includes:

```text
dns:query;ignoreAAAA
drop
tcp
flow
icmp
http
```

Example metric families include:

```text
hubble_flows_processed_total
hubble_drop_total
hubble_tcp_flags_total
hubble_http_requests_total
hubble_dns_queries_total
```

These metrics are useful for understanding network behavior between workloads, identifying dropped traffic, and observing application-level network activity.

## 9. How the Metrics Collection Works Together

The five jobs provide different layers of monitoring.

| Component | Monitoring Layer | Main Question |
|---|---|---|
| Node Exporter | Operating system | Is the node healthy in terms of CPU, memory, disk, and network? |
| kube-state-metrics | Kubernetes resources | Are Pods, Deployments, and other Kubernetes objects healthy? |
| Cilium Agent | Kubernetes networking | Is Cilium functioning correctly on each node? |
| Cilium Operator | Cluster-level networking management | Are Cilium's cluster-level controllers operating correctly? |
| Hubble Metrics | Network observability | What is happening in the network traffic between workloads? |

These sources complement each other.

For example, if an application Pod becomes unavailable:

1. Node Exporter can show whether the underlying node has CPU or memory pressure.
2. kube-state-metrics can show the Pod's current state and restart count.
3. Cilium Agent metrics can help investigate networking or datapath issues.
4. Hubble Metrics can help investigate traffic drops, policy verdicts, DNS, or HTTP activity.
5. Cilium Operator metrics can help investigate cluster-level Cilium controller activity.

## 10. Target Health and Troubleshooting

Prometheus exposes a built-in `up` metric for every scrape target.

The values mean:

| Value | Meaning |
|---:|---|
| `1` | The last scrape was successful. |
| `0` | The last scrape failed. |

For example:

```promql
up{job="node-exporter"}
```

Returns the scrape status of all Node Exporter targets.

To inspect Cilium Agent targets:

```promql
up{job="cilium-agent"}
```

To inspect Hubble Metrics targets:

```promql
up{job="hubble-metrics"}
```

To inspect all targets grouped by job:

```promql
sum by (job) (up)
```

### Current Network Access Requirements

Prometheus runs on:

```text
stage-workerf1
```

The following TCP ports are used for scraping:

| Destination | Port | Component |
|---|---:|---|
| Node Exporter Pod IPs | 9100 | Node Exporter |
| kube-state-metrics endpoint | 8080 and 8081 | kube-state-metrics |
| Kubernetes node IPs | 9962 | Cilium Agent |
| Cilium Operator endpoints | 9963 | Cilium Operator |
| Kubernetes node IPs | 9965 | Hubble Metrics |

The required network path must allow Prometheus to connect to the corresponding metrics endpoints.

During the initial monitoring validation, Node Exporter and kube-state-metrics targets were UP, and both Cilium Operator targets were UP.

Some Cilium Agent and Hubble Metrics targets experienced connection timeouts on ports `9962` and `9965`.

This indicated a connectivity issue between the Prometheus Pod and the affected node metrics endpoints, rather than a Kubernetes service-discovery problem.

After the required network access is granted, the affected targets should be checked again.

## 11. Prometheus Components Disabled in Helm

The following chart-managed components are disabled:

```yaml
alertmanager:
  enabled: false

kube-state-metrics:
  enabled: false

prometheus-node-exporter:
  enabled: false

prometheus-pushgateway:
  enabled: false
```

This is intentional.

Node Exporter and kube-state-metrics are managed separately in the monitoring deployment, rather than being installed as dependencies of the Prometheus Helm chart.

Alertmanager and Pushgateway are not part of the current monitoring deployment.

## 12. Final Architecture Summary

Prometheus runs as a single Pod on `stage-workerf1` and uses Kubernetes endpoint discovery to find the metrics endpoints.

It scrapes:

- Node Exporter through individual Pod IPs.
- kube-state-metrics through its Service endpoints.
- Cilium Agent through node IPs on port `9962`.
- Cilium Operator through its two replica endpoints on port `9963`.
- Hubble Metrics through node IPs on port `9965`.

All targets are scraped every 30 seconds, with a maximum scrape duration of 10 seconds.

The collected metrics are stored in Prometheus persistent storage and retained for up to two days, subject to the 12 GB retention-size limit.

This provides monitoring across the operating system, Kubernetes resources, Cilium networking, and workload network traffic.