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

```text
172.25.3.194
172.25.3.195
172.25.3.196
172.25.3.197
172.25.3.198
172.25.9.114
172.25.9.115
172.25.25.18
172.25.25.19
```

### Destination

```text
172.25.9.82   repository.crouseco.com
172.25.2.242  git.crouseco.com
172.25.2.243  harbor.crouseco.com
```

### Purpose

Kubernetes nodes require HTTPS access to internal infrastructure services for:

* Container image retrieval
* Package retrieval
* Git repository access
* Kubernetes and application deployment resources
* Internal repository and registry communication

The access is required from all nodes because workloads and Kubernetes components may run on any worker node.

---

# 3.2 Worker Nodes → Control Plane

**Protocol:** TCP

**Port:** 6443

### Source

Worker nodes:

```text
172.25.3.197
172.25.3.198
172.25.9.114
172.25.9.115
172.25.25.18
172.25.25.19
```

### Destination

Control-plane nodes:

```text
172.25.3.194
172.25.3.195
172.25.3.196
```

### Purpose

This access is used for communication with the Kubernetes API Server.

Worker nodes require API Server connectivity for normal Kubernetes cluster operation, including registration, state synchronization and API interactions.

> Current cluster configuration uses the Kubernetes control-plane endpoint `172.25.3.199:7443`. Therefore, the existing `6443` rule should be reviewed against the final HA/API endpoint configuration to determine whether direct access to port 6443 is still required.

---

# 3.3 Control Plane → Worker Nodes

**Protocol:** TCP

**Port:** 10250

### Source

Control-plane nodes:

```text
172.25.3.194
172.25.3.195
172.25.3.196
```

### Destination

Worker nodes:

```text
172.25.3.197
172.25.3.198
172.25.9.114
172.25.9.115
172.25.25.18
172.25.25.19
```

### Purpose

Port 10250 is used by the Kubernetes control plane to communicate with the kubelet running on worker nodes.

This communication is required for Kubernetes node management and kubelet-related operations.

---

# 3.4 Kubernetes Node ↔ Kubernetes Node

## Cilium Health

**Protocol:** TCP

**Port:** 4240

**Direction:** Bidirectional

### Source

All Kubernetes nodes:

```text
172.25.3.194
172.25.3.195
172.25.3.196
172.25.3.197
172.25.3.198
172.25.9.114
172.25.9.115
172.25.25.18
172.25.25.19
```

### Destination

All Kubernetes nodes.

### Purpose

Cilium uses TCP port 4240 for node health connectivity.

The connection must be available between Kubernetes nodes so that Cilium can determine the health and reachability of other nodes.

This traffic is especially important across the FRONTEND, BACKEND and DMZ network zones.

---

# 3.5 Kubernetes Node ↔ Kubernetes Node

## Cilium Geneve

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

For example:

```text
Pod on WorkerD1

172.25.25.18

       |

       | Cilium Geneve
       | UDP 6081

       v

WorkerF2

172.25.3.198

       |

       v

Pod on WorkerF2
```

Therefore, UDP 6081 must be allowed between all Kubernetes nodes.

---

# 4. Why Node-to-Node Access Is Required

Kubernetes workloads are not permanently tied to a particular network zone or physical server.

A workload running on a DMZ worker may need to communicate with a workload running on a FRONTEND or BACKEND worker.

For example:

```text
argocd-server

    |

    | WorkerD1
    | 172.25.25.18

    | Cilium overlay

    | WorkerF2
    | 172.25.3.198

    |

    v

Redis
```

Because the two workloads are running on different Kubernetes nodes, Cilium must provide connectivity between those nodes.

This is why the following access must be **bidirectional**:

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

# 5. Connectivity Validation Script

The following script is used to validate the network access from each Kubernetes node.

## Script Location

```text
/home/user/check-k8s-node-connectivity.sh
```

The script checks:

```text
TCP 4240  → Cilium health

UDP 6081  → Cilium Geneve

TCP 443   → Repository / Git / Harbor
```

## Script

```bash
#!/bin/bash

NODES=(
    "stage-masterf1 172.25.3.194"
    "stage-masterf2 172.25.3.195"
    "stage-masterf3 172.25.3.196"
    "stage-workerf1 172.25.3.197"
    "stage-workerf2 172.25.3.198"
    "stage-workerb1 172.25.9.114"
    "stage-workerb2 172.25.9.115"
    "stage-workerd1 172.25.25.18"
    "stage-workerd2 172.25.25.19"
)

INFRA=(
    "repository.crouseco.com 172.25.9.82"
    "git.crouseco.com 172.25.2.242"
    "harbor.crouseco.com 172.25.2.243"
)

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo
echo "============================================================"
echo " Kubernetes Node Connectivity Check"
echo "============================================================"
echo "Hostname : $(hostname)"
echo "Local IP : $LOCAL_IP"
echo "============================================================"
echo

echo "TCP 4240 - Cilium Health"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-20s %-16s TCP/4240  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    if timeout 3 bash -c "</dev/tcp/$IP/4240" 2>/dev/null; then
        printf "%-20s %-16s TCP/4240  OK\n" "$NAME" "$IP"
    else
        printf "%-20s %-16s TCP/4240  FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "UDP 6081 - Cilium Geneve"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-20s %-16s UDP/6081  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    if timeout 3 bash -c "</dev/udp/$IP/6081" 2>/dev/null; then
        printf "%-20s %-16s UDP/6081  SENT\n" "$NAME" "$IP"
    else
        printf "%-20s %-16s UDP/6081  FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "TCP 443 - Infrastructure"
echo "------------------------------------------------------------"

for ENTRY in "${INFRA[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if timeout 3 bash -c "</dev/tcp/$IP/443" 2>/dev/null; then
        printf "%-25s %-16s TCP/443   OK\n" "$NAME" "$IP"
    else
        printf "%-25s %-16s TCP/443   FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "============================================================"
echo "Check completed."
echo "============================================================"
echo
```

---

# 6. Installing the Script

If the script is transferred from a Windows workstation, convert the line endings before executing it:

```bash
sed -i 's/\r$//' /home/user/check-k8s-node-connectivity.sh
```

Make it executable:

```bash
chmod +x /home/user/check-k8s-node-connectivity.sh
```

---

# 7. Creating a Shortcut Command

To make the script easier to run, create a symbolic link in `/usr/local/bin`.

```bash
sudo ln -s /home/user/check-k8s-node-connectivity.sh /usr/local/bin/k8s-check
```

This creates the following relationship:

```text
/usr/local/bin/k8s-check
        |
        | symbolic link
        v
/home/user/check-k8s-node-connectivity.sh
```

The script remains in `/home/user`. The file in `/usr/local/bin` is only a shortcut to the original script.

Because `/usr/local/bin` is normally included in the system `PATH`, the script can then be executed using:

```bash
k8s-check
```

from any directory.

The symbolic link can be verified with:

```bash
ls -l /usr/local/bin/k8s-check
```

Expected output:

```text
k8s-check -> /home/user/check-k8s-node-connectivity.sh
```

If the original script is modified, the `k8s-check` command automatically uses the updated script because it points to the original file.

---

# 8. Running the Script

The script should be executed on **each Kubernetes node**, including both control-plane and worker nodes.

Direct execution using the full path:

```bash
/home/user/check-k8s-node-connectivity.sh
```

Alternatively, using the shortcut:

```bash
k8s-check
```

The shortcut is the preferred method for regular connectivity checks because it avoids entering the full script path.

The script can also be executed explicitly through Bash:

```bash
bash /home/user/check-k8s-node-connectivity.sh
```

---

# 9. Interpreting Results

### TCP 4240

```text
TCP/4240 OK
```

Indicates that TCP connectivity to the target node's Cilium health endpoint is available.

```text
TCP/4240 FAILED
```

Indicates that TCP connectivity to the target node is unavailable or blocked.

### UDP 6081

```text
UDP/6081 SENT
```

Indicates that the local operating system was able to send a UDP packet toward the target.

> UDP does not provide a connection handshake, so `SENT` does not prove that the remote node received the packet.

```text
UDP/6081 FAILED
```

Indicates that the local UDP send attempt failed.

### TCP 443

```text
TCP/443 OK
```

Indicates that HTTPS/TCP connectivity to the infrastructure service is available.

```text
TCP/443 FAILED
```

Indicates that TCP connectivity to the infrastructure service is unavailable or blocked.

---

# 10. Cilium Validation

Network-level port testing should be combined with Cilium's own health information.

From a control-plane node:

```bash
kubectl exec -n kube-system <cilium-pod> -- cilium-dbg status
```

Check:

```text
Cluster health
```

For detailed node health:

```bash
kubectl exec -n kube-system <cilium-pod> -- cilium-health status
```

The expected result is that Kubernetes nodes are reachable through Cilium.

---

# 11. Current Troubleshooting Context

The current cluster has shown a connectivity problem involving the DMZ workers.

For example:

```text
WorkerD1

172.25.25.18

       |

       | TCP 4240

       X

       |

Frontend/Backend nodes
```

while communication between the two DMZ workers is available.

Cilium has reported the DMZ nodes as unreachable from the other cluster nodes.

This makes the following network access rules particularly important:

```text
All Kubernetes Nodes ↔ All Kubernetes Nodes

TCP 4240

All Kubernetes Nodes ↔ All Kubernetes Nodes

UDP 6081
```

The purpose of the connectivity script is to provide evidence from the operating-system/network level so that firewall or network restrictions can be distinguished from Kubernetes or application configuration problems.

---

# 12. Access Summary

| Source           | Destination           | Protocol/Port | Purpose                        |
| ---------------- | --------------------- | ------------- | ------------------------------ |
| Kubernetes Nodes | Repository/Git/Harbor | TCP 443       | Internal infrastructure access |
| Workers          | Control Plane         | TCP 6443      | Kubernetes API access          |
| Control Plane    | Workers               | TCP 10250     | Kubelet communication          |
| Kubernetes Nodes | Kubernetes Nodes      | TCP 4240      | Cilium health                  |
| Kubernetes Nodes | Kubernetes Nodes      | UDP 6081      | Cilium Geneve overlay          |

The most important requirement for **cross-node Cilium networking** is:

```text
TCP 4240 ↔ TCP 4240

UDP 6081 ↔ UDP 6081
```

between all Kubernetes nodes.
