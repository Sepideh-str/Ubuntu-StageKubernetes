# Kubernetes Network Access Requirements and Connectivity Validation

## 1. Purpose

This document describes the network access required for the Kubernetes cluster and explains the purpose of each requested connection.

The cluster spans three network zones:

* FRONTEND
* BACKEND
* DMZ

Because Kubernetes workloads can communicate across nodes in different zones, the required Kubernetes and Cilium traffic must be permitted between the relevant nodes.

---

# 2. Kubernetes Nodes

| Node     | IP Address   | Zone     | Role          |
| -------- | ------------ | -------- | ------------- |
| MasterF1 | 172.25.3.194 | FRONTEND | Control Plane |
| MasterF2 | 172.25.3.195 | FRONTEND | Control Plane |
| MasterF3 | 172.25.3.196 | FRONTEND | Control Plane |
| WorkerF1 | 172.25.3.197 | FRONTEND | Worker        |
| WorkerF2 | 172.25.3.198 | FRONTEND | Worker        |
| WorkerB1 | 172.25.9.114 | BACKEND  | Worker        |
| WorkerB2 | 172.25.9.115 | BACKEND  | Worker        |
| WorkerD1 | 172.25.25.18 | DMZ      | Worker        |
| WorkerD2 | 172.25.25.19 | DMZ      | Worker        |

---

# 3. Required Network Access

## 3.1 Kubernetes Nodes → Infrastructure Services

**Protocol:** TCP
**Port:** 443

### Source

All Kubernetes nodes:

* 172.25.3.194
* 172.25.3.195
* 172.25.3.196
* 172.25.3.197
* 172.25.3.198
* 172.25.9.114
* 172.25.9.115
* 172.25.25.18
* 172.25.25.19

### Destination

* 172.25.9.82 — repository.crouseco.com
* 172.25.2.242 — git.crouseco.com
* 172.25.2.243 — harbor.crouseco.com

### Purpose

Kubernetes nodes require HTTPS access to internal infrastructure services for:

* Container image retrieval
* Package retrieval
* Git repository access
* Kubernetes and application deployment resources
* Internal repository and registry communication

The access is required from all nodes because workloads and Kubernetes components may run on any worker node.

---

## 3.2 Worker Nodes → Control Plane

**Protocol:** TCP
**Port:** 6443

### Source

Worker nodes:

* 172.25.3.197
* 172.25.3.198
* 172.25.9.114
* 172.25.9.115
* 172.25.25.18
* 172.25.25.19

### Destination

Control-plane nodes:

* 172.25.3.194
* 172.25.3.195
* 172.25.3.196

### Purpose

This access is used for communication with the Kubernetes API Server.

Worker nodes require API Server connectivity for normal Kubernetes cluster operation, including registration, state synchronization and API interactions.

> Current cluster configuration uses the Kubernetes control-plane endpoint `172.25.3.199:7443`. Therefore, the existing `6443` rule should be reviewed against the final HA/API endpoint configuration to determine whether direct access to port 6443 is still required.

---

## 3.3 Control Plane → Worker Nodes

**Protocol:** TCP
**Port:** 10250

### Source

Control-plane nodes:

* 172.25.3.194
* 172.25.3.195
* 172.25.3.196

### Destination

Worker nodes:

* 172.25.3.197
* 172.25.3.198
* 172.25.9.114
* 172.25.9.115
* 172.25.25.18
* 172.25.25.19

### Purpose

Port 10250 is used by the Kubernetes control plane to communicate with the kubelet running on worker nodes.

This communication is required for Kubernetes node management and kubelet-related operations.

---

# 4. Kubernetes Node ↔ Kubernetes Node

## 4.1 Cilium Health

**Protocol:** TCP
**Port:** 4240
**Direction:** Bidirectional

### Source

All Kubernetes nodes.

### Destination

All Kubernetes nodes.

### Purpose

Cilium uses TCP port 4240 for node health connectivity.

The connection must be available between Kubernetes nodes so that Cilium can determine the health and reachability of other nodes.

This traffic is especially important across the FRONTEND, BACKEND and DMZ network zones.

---

## 4.2 Cilium Geneve

**Protocol:** UDP
**Port:** 6081
**Direction:** Bidirectional

### Source

All Kubernetes nodes.

### Destination

All Kubernetes nodes.

### Purpose

The Kubernetes cluster uses Cilium with the Geneve tunnel protocol.

UDP 6081 carries Geneve encapsulated traffic between Kubernetes nodes.

This allows pods running on different nodes to communicate through the Cilium overlay network.

Therefore, UDP 6081 must be allowed between all Kubernetes nodes.

---

# 5. Why Node-to-Node Access Is Required

Kubernetes workloads are not permanently tied to a particular network zone or physical server.

A workload running on a DMZ worker may need to communicate with a workload running on a FRONTEND or BACKEND worker.

For example, an Argo CD server and Redis instance may run on different Kubernetes nodes. Cilium must provide connectivity between those nodes for the workloads to communicate.

Because workloads can run on different nodes, the following access must be **bidirectional**:

```text
All Kubernetes Nodes
        ↕
TCP 4240
        ↕
All Kubernetes Nodes
```

and:

```text
All Kubernetes Nodes
        ↕
UDP 6081
        ↕
All Kubernetes Nodes
```

---

# 6. Connectivity Validation

Network connectivity is validated using dedicated scripts executed directly from the Kubernetes nodes.

Two scripts are used:

* `check-k8s-node-connectivity.sh` — general Kubernetes node connectivity check.
* `Masters-check-k8s-node-connectivity.sh` — master/control-plane connectivity check.

The scripts provide OS/network-level validation to help distinguish firewall or network restrictions from Kubernetes or application configuration problems.

---

## 6.1 General Node Connectivity Check

**Script:**

`check-k8s-node-connectivity.sh`

This script is intended to be executed on Kubernetes nodes and validates:

| Protocol / Port | Purpose                   |
| --------------- | ------------------------- |
| TCP 4240        | Cilium health             |
| UDP 6081        | Cilium Geneve             |
| TCP 443         | Repository / Git / Harbor |

The script should be executed from the relevant Kubernetes nodes to validate outbound connectivity.

---

## 6.2 Master Connectivity Check

**Script:**

`Masters-check-k8s-node-connectivity.sh`

This script is specifically intended for the three Kubernetes control-plane nodes:

* MasterF1 — 172.25.3.194
* MasterF2 — 172.25.3.195
* MasterF3 — 172.25.3.196

It validates the connectivity required from the control plane:

| Protocol / Port | Source | Destination    | Purpose                   |
| --------------- | ------ | -------------- | ------------------------- |
| TCP 4240        | Master | All nodes      | Cilium health             |
| UDP 6081        | Master | All nodes      | Cilium Geneve             |
| TCP 6443        | Master | Other masters  | Kubernetes API            |
| TCP 7443        | Master | 172.25.3.199   | Kubernetes API endpoint   |
| TCP 10250       | Master | Workers        | Kubelet communication     |
| TCP 443         | Master | Infrastructure | Repository / Git / Harbor |
| DNS             | Master | DNS server     | Name resolution           |

The master connectivity check should be executed on **MasterF1, MasterF2 and MasterF3**.

Running the check from each master provides visibility into connectivity from each control-plane node rather than testing only from a single source.

---

# 7. Installing the Connectivity Scripts

If the scripts are transferred from a Windows workstation, convert the line endings before executing them:

```text
sed -i 's/\r$//' <script-path>
```

Make the script executable:

```text
chmod +x <script-path>
```

The scripts should then be tested directly before creating a shortcut command.

---

# 8. Creating a Shortcut Command

A symbolic link can be created in `/usr/local/bin` to make the connectivity check easier to execute.

For example:

```text
/usr/local/bin/k8s-check
```

can point to the general connectivity script.

The shortcut allows the script to be executed using:

```text
k8s-check
```

from any directory.

The symbolic link can be verified with:

```text
ls -l /usr/local/bin/k8s-check
```

---

# 9. Running the Checks

The general connectivity script can be executed using:

```text
k8s-check
```

The master-specific script can be executed directly using its script path or through a dedicated shortcut if configured.

The master-specific check should be run on:

* MasterF1
* MasterF2
* MasterF3

The general node check should be used when validating connectivity from worker nodes.

---

# 10. Interpreting Results

## TCP 4240

`TCP/4240 OK`

Indicates that TCP connectivity to the target node's Cilium health endpoint is available.

`TCP/4240 FAILED`

Indicates that TCP connectivity to the target node is unavailable or blocked.

---

## UDP 6081

`UDP/6081 SENT`

Indicates that the local operating system was able to send a UDP packet toward the target.

> UDP does not provide a connection handshake, so `SENT` does not prove that the remote node received the packet.

`UDP/6081 FAILED`

Indicates that the local UDP send attempt failed.

For definitive validation of UDP 6081, packet capture and Cilium health information should also be used.

---

## TCP 443

`TCP/443 OK`

Indicates that HTTPS/TCP connectivity to the infrastructure service is available.

`TCP/443 FAILED`

Indicates that TCP connectivity to the infrastructure service is unavailable or blocked.

---

# 11. Cilium Validation

Network-level port testing should be combined with Cilium's own health information.

From a control-plane node, check the Cilium status and health information.

Check:

* Cluster health
* Node reachability
* Cilium health status

The expected result is that Kubernetes nodes are reachable through Cilium.

---

# 12. Current Troubleshooting Context

The current cluster has shown a connectivity problem involving the DMZ workers.

Cilium has reported the DMZ nodes as unreachable from other cluster nodes, while communication between the two DMZ workers is available.

This makes the following network access rules particularly important:

```text
All Kubernetes Nodes ↔ All Kubernetes Nodes
TCP 4240
```

and:

```text
All Kubernetes Nodes ↔ All Kubernetes Nodes
UDP 6081
```

The connectivity scripts provide OS/network-level evidence that can be used to determine whether the problem is related to firewall or network restrictions rather than Kubernetes or application configuration.

---

# 13. Access Summary

| Source           | Destination               | Protocol / Port | Purpose               |
| ---------------- | ------------------------- | --------------- | --------------------- |
| Kubernetes Nodes | Repository / Git / Harbor | TCP 443         | Infrastructure access |
| Workers          | Control Plane             | TCP 6443        | Kubernetes API access |
| Control Plane    | Workers                   | TCP 10250       | Kubelet communication |
| Kubernetes Nodes | Kubernetes Nodes          | TCP 4240        | Cilium health         |
| Kubernetes Nodes | Kubernetes Nodes          | UDP 6081        | Cilium Geneve overlay |

The most important requirements for **cross-node Cilium networking** are:

```text
TCP 4240 ↔ TCP 4240
UDP 6081 ↔ UDP 6081
```

between all Kubernetes nodes, including communication across the FRONTEND, BACKEND and DMZ zones.
