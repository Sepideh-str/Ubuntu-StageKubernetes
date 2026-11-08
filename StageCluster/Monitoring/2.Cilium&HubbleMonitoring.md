# Cilium Monitoring

## 1. Overview

Cilium monitoring provides visibility into Kubernetes networking, network policies, traffic flows, and the health of Cilium components.

The monitoring architecture consists of three main components:

- **Cilium Agent:** Monitors and manages networking on each Kubernetes node.
- **Cilium Operator:** Performs cluster-wide Cilium management and coordination tasks.
- **Hubble:** Provides network-flow visibility and observability across the Kubernetes cluster.

Prometheus collects metrics from these components, while Grafana provides dashboards and visualization.

## 2. Monitoring Architecture

The monitoring architecture is organized as follows:

```text
                 Kubernetes Cluster
                         |
          +--------------+--------------+
          |              |              |
     Cilium Agent   Cilium Operator   Hubble
      (all nodes)    (2 replicas)   (Relay + UI)
          |              |              |
       :9962          :9963          :9965
          |              |              |
          +--------------+--------------+
                         |
                     Prometheus
                         |
                      Grafana
                         |
                       Alerts
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| Cilium Agent | Node-level networking, eBPF datapath, network policies and connectivity |
| Cilium Operator | Cluster-wide Cilium management, IPAM operations (depending on IPAM mode), and coordination |
| Hubble | Network-flow observability and traffic visibility |
| Hubble Relay | Aggregates flow information from Cilium agents |
| Hubble UI | Web interface for exploring network flows |
| Prometheus | Metrics collection and storage |
| Grafana | Metrics visualization and dashboards |

## 3. Kubernetes Cluster Environment

Kubernetes version: `v1.36.4`

Cilium version: `v1.20.2`

The cluster contains nine Kubernetes nodes.

| Node | IP address | Zone |
|---|---|---|
| stage-masterf1 | 172.25.3.194 | Control plane |
| stage-masterf2 | 172.25.3.195 | Control plane |
| stage-masterf3 | 172.25.3.196 | Control plane |
| stage-workerf1 | 172.25.3.197 | Frontend |
| stage-workerf2 | 172.25.3.198 | Frontend |
| stage-workerb1 | 172.25.9.114 | Backend |
| stage-workerb2 | 172.25.9.115 | Backend |
| stage-workerd1 | 172.25.25.18 | DMZ |
| stage-workerd2 | 172.25.25.19 | DMZ |

Cilium Agent runs as a DaemonSet, providing one agent on every Kubernetes node.

## 4. Cilium Agent Monitoring

### 4.1 Purpose

The Cilium Agent is responsible for managing networking on its local Kubernetes node.

It handles tasks such as:

- eBPF datapath management.
- Network policy enforcement.
- Pod connectivity.
- Network traffic processing.
- Network packet drops and forwarding.
- DNS and Layer 7 visibility when enabled.

Prometheus collects metrics from each Cilium Agent independently.

### 4.2 Metrics endpoint

| Setting | Value |
|---|---|
| Kubernetes Service | cilium-agent |
| Service type | Headless ClusterIP |
| Metrics port | TCP 9962 |
| Metrics path | `/metrics` |
| Protocol | HTTP |
| Prometheus scraping | Enabled |

The metrics endpoint is exposed on each Kubernetes node.

Example:

```text
http://172.25.3.194:9962/metrics
http://172.25.3.195:9962/metrics
http://172.25.3.196:9962/metrics
http://172.25.3.197:9962/metrics
http://172.25.3.198:9962/metrics
http://172.25.9.114:9962/metrics
http://172.25.9.115:9962/metrics
http://172.25.25.18:9962/metrics
http://172.25.25.19:9962/metrics
```

### 4.3 Prometheus configuration

All nine Cilium Agent endpoints must be configured as Prometheus scrape targets.

Example static configuration:

```yaml
scrape_configs:
  - job_name: cilium-agent
    metrics_path: /metrics
    static_configs:
      - targets:
          - 172.25.3.194:9962
          - 172.25.3.195:9962
          - 172.25.3.196:9962
          - 172.25.3.197:9962
          - 172.25.3.198:9962
          - 172.25.9.114:9962
          - 172.25.9.115:9962
          - 172.25.25.18:9962
          - 172.25.25.19:9962
```

Each target provides metrics from its respective Cilium Agent.

Scraping only one node does not provide complete cluster-wide Agent metrics.

### 4.4 Example metrics

Cilium exposes Prometheus metrics related to:

- Datapath processing.
- Network packet and byte counts.
- Packet drops.
- Policy verdicts.
- DNS activity.
- eBPF maps and resource usage.
- Agent errors and operational activity.

The exact available metrics depend on enabled Cilium features and configuration.

## 5. Cilium Operator Monitoring

### 5.1 Purpose

The Cilium Operator is responsible for cluster-wide Cilium management tasks.

Unlike Cilium Agents, which run on every node, the Operator performs tasks that do not need to be independently executed by every node.

Its responsibilities include:

- Cluster-wide IP Address Management (depending on the configured IPAM mode).
- Node-related synchronization.
- Cilium resource management.
- Certain cleanup and garbage-collection operations.
- Cluster-wide coordination.

The Operator does not replace the Cilium Agents.

### 5.2 Operator replicas

The current deployment has two Operator replicas.

The intended placement is one replica on each frontend worker:

| Replica | Intended node | IP address |
|---|---|---|
| Operator 1 | stage-workerf1 | 172.25.3.197 |
| Operator 2 | stage-workerf2 | 172.25.3.198 |

The two replicas provide availability. Leader election coordinates leader-controlled operations.

**Placement status:** The frontend placement is the intended configuration. It must be verified after applying the Helm upgrade.

### 5.3 Metrics endpoint

| Setting | Value |
|---|---|
| Kubernetes Service | cilium-operator |
| Service type | Headless ClusterIP |
| Metrics port | TCP 9963 |
| Metrics path | `/metrics` |
| Protocol | HTTP |
| Metrics enabled | Yes |

Current Operator endpoints, before the planned frontend migration:

```text
172.25.25.19:9963
172.25.9.115:9963
```

Expected endpoints after the frontend migration:

```text
172.25.3.197:9963
172.25.3.198:9963
```

Prometheus should scrape both Operator replicas.

### 5.4 Prometheus configuration

After the frontend migration is complete:

```yaml
scrape_configs:
  - job_name: cilium-operator
    metrics_path: /metrics
    static_configs:
      - targets:
          - 172.25.3.197:9963
          - 172.25.3.198:9963
```

### 5.5 Example metrics

Operator metrics help monitor:

- Operator availability.
- Reconciliation and management activity.
- IPAM-related operations.
- Errors and failed operations.
- Kubernetes resource-management activity.

The actual metric names depend on the Cilium version and enabled features.

## 6. Hubble Monitoring

### 6.1 Purpose

Hubble is Cilium's network observability platform.

It provides visibility into communication between Kubernetes workloads and helps identify:

- Which Pod communicates with another Pod.
- Which namespace generates traffic.
- Which network protocols are used.
- Whether traffic is allowed or dropped.
- DNS queries and responses.
- Network policy verdicts.
- Layer 7 traffic information when applicable.

Hubble complements Prometheus metrics by providing detailed network-flow information.

### 6.2 Hubble components

**Hubble Server**

Runs as part of each Cilium Agent and collects network-flow information from the local node.

**Hubble Relay**

Connects to Hubble servers across the cluster and aggregates flow information, providing a cluster-wide view.

**Hubble UI**

Provides a web interface to explore network flows, workloads, namespaces, and communication relationships.

**Hubble Metrics**

Exposes selected network-flow information as Prometheus metrics.

These components have different responsibilities. Hubble UI is not required for Prometheus metrics collection.

### 6.3 Hubble services

The current Kubernetes services in `kube-system` include:

| Service | Type | Port | Purpose |
|---|---|---:|---|
| hubble-peer | ClusterIP | 443 | Hubble peer discovery and access |
| hubble-relay | ClusterIP | 80 | Hubble Relay API |
| hubble-ui | ClusterIP | 80 | Hubble UI web interface |
| hubble-metrics | Headless ClusterIP | 9965 | Hubble Prometheus metrics |

Hubble Relay communicates with the Hubble servers on the Cilium Agents. The agent-side Hubble peer endpoint normally uses TCP 4244.

### 6.4 Hubble metrics configuration

The current Cilium configuration includes:

```yaml
hubble:
  enabled: true
```

The observed Cilium configuration includes:

```yaml
enable-hubble-open-metrics: "false"

hubble-metrics: dns:query;ignoreAAAA drop tcp flow icmp http

hubble-metrics-server: :9965

hubble-metrics-server-enable-tls: "false"
```

The selected metrics include:

- DNS query metrics.
- Dropped traffic.
- TCP activity.
- Network flow metrics.
- ICMP activity.
- HTTP activity.

The exact metric set depends on the enabled Hubble metrics configuration.

### 6.5 Hubble metrics endpoint

| Setting | Value |
|---|---|
| Kubernetes Service | hubble-metrics |
| Service type | Headless ClusterIP |
| Metrics port | TCP 9965 |
| Metrics path | `/metrics` |
| Protocol | HTTP |
| TLS | Disabled for this metrics endpoint |

The metrics endpoint is exposed by the Cilium Agents on the nodes.

Prometheus should scrape all nine node endpoints:

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

### 6.6 Prometheus configuration

```yaml
scrape_configs:
  - job_name: hubble
    metrics_path: /metrics
    static_configs:
      - targets:
          - 172.25.3.194:9965
          - 172.25.3.195:9965
          - 172.25.3.196:9965
          - 172.25.3.197:9965
          - 172.25.3.198:9965
          - 172.25.9.114:9965
          - 172.25.9.115:9965
          - 172.25.25.18:9965
          - 172.25.25.19:9965
```

### 6.7 Hubble UI

Hubble UI is exposed through its Kubernetes Service:

```text
Namespace: kube-system
Service: hubble-ui
Port: 80
Type: ClusterIP
```

The UI is separate from the Prometheus metrics endpoint.

Access to Hubble UI should be provided through an appropriate internal access method, such as port-forwarding, an ingress, or a Gateway API route.

## 7. Firewall Requirements

For an external Prometheus server to scrape the metrics endpoints directly, network access must be allowed from the Prometheus server to the relevant Kubernetes node or Pod IP addresses.

### 7.1 Cilium Agent metrics

| Source | Destination | Protocol | Port |
|---|---|---|---:|
| Prometheus | All 9 Kubernetes nodes | TCP | 9962 |

### 7.2 Hubble metrics

| Source | Destination | Protocol | Port |
|---|---|---|---:|
| Prometheus | All 9 Kubernetes nodes | TCP | 9965 |

### 7.3 Cilium Operator metrics

After the planned frontend migration:

| Source | Destination | Protocol | Port |
|---|---|---|---:|
| Prometheus | 172.25.3.197 | TCP | 9963 |
| Prometheus | 172.25.3.198 | TCP | 9963 |

Before migration, the Operator endpoints are `172.25.25.19` and `172.25.9.115`.

### 7.4 Hubble Relay connectivity

Hubble Relay needs connectivity to the Hubble peer endpoints on the Cilium Agents.

| Source | Destination | Protocol | Port |
|---|---|---|---:|
| Hubble Relay | Cilium Agent nodes | TCP | 4244 |

The existing Hubble peer Kubernetes Service uses TCP 443 for peer discovery/access. The exact network path depends on the configured service and peer settings.

### 7.5 Important networking notes

- No NodePort is required for the metrics endpoints when they are directly reachable through their node or Pod IPs.
- The actual listening and routing behavior depends on `hostNetwork`, host ports, and the Cilium chart configuration.
- A successful local `curl` does not prove external Prometheus connectivity.
- Firewall rules must use the actual source IP of the Prometheus server.
- If Prometheus runs inside the cluster, Kubernetes service discovery and internal routing can be used instead of external firewall access.

## 8. Validation and Troubleshooting

### 8.1 Check Cilium Agent Pods

```bash
kubectl get pods -n kube-system -o wide | grep cilium-
```

There should be one Cilium Agent on each Kubernetes node.

### 8.2 Test Cilium Agent metrics

```bash
curl -sS http://172.25.3.197:9962/metrics | head
```

### 8.3 Check Operator Pods

```bash
kubectl get pods -n kube-system -o wide | grep cilium-operator
```

### 8.4 Test Operator metrics

```bash
curl -sS http://172.25.25.19:9963/metrics | head
curl -sS http://172.25.9.115:9963/metrics | head
```

Use the frontend IP addresses after the Operator migration.

### 8.5 Test Hubble metrics

```bash
curl -sS http://172.25.3.197:9965/metrics | head
```

### 8.6 Check Hubble Relay

```bash
kubectl get pods -n kube-system | grep hubble-relay
kubectl logs -n kube-system deployment/hubble-relay --tail=50
```

### 8.7 Check Hubble UI

```bash
kubectl get pods -n kube-system | grep hubble-ui
kubectl get service hubble-ui -n kube-system
```

### 8.8 Verify Prometheus targets

In the Prometheus web interface, open:

```text
Status → Targets
```

Verify that the following scrape jobs are healthy:

- `cilium-agent`
- `cilium-operator`
- `hubble`

Targets should report `UP`.

## 9. Monitoring Recommendations

The following areas should be covered by Grafana dashboards and alerting.

| Monitoring area | Component |
|---|---|
| Agent availability | Cilium Agent |
| Agent errors and restarts | Cilium Agent |
| Packet drops | Cilium Agent / Hubble |
| Network policy verdicts | Cilium Agent / Hubble |
| DNS activity | Hubble |
| TCP and ICMP activity | Hubble |
| HTTP request activity | Hubble |
| Operator availability | Cilium Operator |
| Operator errors | Cilium Operator |
| IPAM-related activity | Cilium Operator |

Recommended alerts:

1. Cilium Agent unavailable on a Kubernetes node.
2. Cilium Operator replicas unavailable.
3. Hubble metrics endpoint unavailable.
4. Hubble Relay unavailable.
5. Unexpected increase in dropped network traffic.
6. Significant increase in DNS failures.
7. Prometheus scrape failures.

## 10. Current Implementation Status

| Item | Status |
|---|---|
| Cilium v1.20.2 | Installed |
| Cilium Agent DaemonSet | Running on all 9 nodes |
| Agent Prometheus metrics | Enabled on port 9962 |
| Cilium Operator | 2 replicas running |
| Operator metrics | Enabled on port 9963 |
| Operator frontend placement | Planned; Helm upgrade and verification pending |
| Hubble | Enabled |
| Hubble Relay | Installed |
| Hubble UI | Installed |
| Hubble metrics | Configured on port 9965 |
| Prometheus firewall access | To be confirmed |
| Prometheus scrape jobs | To be configured/verified |
| Grafana dashboards | To be configured |
| Alerting | To be configured |

## 11. Summary

Cilium monitoring uses three complementary sources of observability:

- **Cilium Agent metrics (9962):** Monitor networking and policy enforcement on every Kubernetes node.
- **Cilium Operator metrics (9963):** Monitor cluster-wide Cilium management operations.
- **Hubble metrics (9965):** Monitor network-flow activity across the cluster.

Hubble Relay and Hubble UI provide additional flow aggregation and visualization capabilities.

Prometheus collects the metrics, and Grafana provides dashboards and alerting.

Together, these components provide visibility into Cilium health, Kubernetes network activity, and network policy behavior.