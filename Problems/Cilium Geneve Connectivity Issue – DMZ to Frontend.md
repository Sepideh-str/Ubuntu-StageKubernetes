# Cilium Geneve Connectivity Issue – DMZ to Frontend

## Problem Summary

The Kubernetes cluster uses **Cilium** as the CNI, with **Geneve tunneling** for pod-to-pod communication between nodes.

The Kubernetes nodes are located in different network zones:

| Zone     | Node Network  |
| -------- | ------------- |
| Frontend | `172.25.3.x`  |
| Backend  | `172.25.9.x`  |
| DMZ      | `172.25.25.x` |

Cilium requires specific network connectivity between Kubernetes nodes, including:

| Protocol |    Port | Purpose              |
| -------- | ------: | -------------------- |
| UDP      |  `6081` | Cilium Geneve tunnel |
| TCP      |  `4240` | Cilium health checks |
| TCP      | `10250` | Kubelet              |
| TCP      |  `6443` | Kubernetes API       |

The main issue is with **UDP 6081 communication between the DMZ and Frontend zones**.

---

## What We Observed

The Backend and Frontend nodes can communicate correctly, and Cilium networking works between those zones.

However, communication involving the DMZ nodes has a problem.

For example:

```text
Worker-D2
172.25.25.19
        |
        | UDP 6081
        |
        v
Worker-F2
172.25.3.198
```

We generated UDP traffic from `Worker-D2` toward `Worker-F2` and captured the traffic on both nodes.

On `Worker-D2`, the UDP 6081 packet was visible leaving the server.

On `Worker-F2`, the corresponding packet was not visible arriving at the server.

This means the packet is being lost somewhere between the two nodes.

---

## What This Proves

The packet capture gives us an important boundary:

```text
Worker-D2
172.25.25.19
     |
     | Packet leaves D2
     v
   ??????
     |
     | Packet does not arrive
     v
Worker-F2
172.25.3.198
```

Therefore, the evidence does **not** indicate that Cilium is simply failing to generate Geneve traffic.

Cilium is generating the traffic.

The problem appears to be somewhere in the network path between the DMZ and Frontend nodes.

Possible locations include:

* Inter-zone firewall
* Network ACL
* Virtual firewall/security policy
* Routing/security infrastructure
* Network virtualization layer
* Other filtering between the DMZ and Frontend networks

The packet capture alone does not identify which device is dropping the packet.

---

## Why Ping/Normal Connectivity Can Still Work

The fact that ICMP or some TCP connections work does not prove that UDP 6081 is allowed.

For example, the network could allow:

```text
DMZ → Frontend

ICMP       ✓
TCP        ✓
UDP 6081   ✗
```

Cilium specifically needs **UDP 6081** for Geneve encapsulation.

Therefore, general server-to-server connectivity is not sufficient to confirm that the Cilium overlay can work.

---

## Important: UDP 6081 vs TCP 6081

Cilium Geneve uses:

```text
UDP 6081
```

It does **not** use TCP 6081.

Therefore, opening:

```text
TCP 6081
```

would not solve the Geneve tunneling problem.

The required rule is:

```text
UDP 6081
```

between the Kubernetes nodes that need to establish Cilium tunnels.

---

## DMZ vs Frontend

The important difference is that communication between Backend and Frontend works, while communication involving the DMZ has the problem.

This suggests that the network policy/path between these zones may be different.

The situation can be summarized as:

```text
Backend ↔ Frontend
Cilium Geneve communication
       ✓


DMZ ↔ Frontend
Cilium Geneve communication
       ✗ / packet disappears
```

This is why the DMZ zone needs to be investigated specifically.

---

## Redis Connectivity Test

We also tested a TCP connection from the DMZ worker:

```text
Worker-D2
172.25.25.19
        |
        | TCP 6379
        v
10.0.4.216
```

The connection timed out:

```text
nc -vz -w 5 10.0.4.216 6379

connect to 10.0.4.216 port 6379 timed out
```

This provides additional evidence that there may be connectivity restrictions affecting traffic originating from the DMZ.

However, this is a separate TCP test and does **not** by itself prove that TCP 6379 is related to the Kubernetes Geneve problem.

The Kubernetes-specific evidence is the UDP 6081 packet capture.

---

## What We Need From the Network Team

Please verify the network path between the following Kubernetes nodes.

### DMZ

```text
Worker-D1   172.25.25.18
Worker-D2   172.25.25.19
```

### Frontend

```text
Master-F1   172.25.3.194
Master-F2   172.25.3.195
Master-F3   172.25.3.196
Worker-F1   172.25.3.197
Worker-F2   172.25.3.198
```

Specifically verify:

### 1. UDP 6081

Confirm that **UDP/6081 is allowed bidirectionally** between the DMZ and Frontend Kubernetes nodes.

```text
DMZ ↔ Frontend
UDP/6081
```

### 2. Firewall / ACL Logs

Check whether any firewall, ACL, or network security device is dropping:

```text
Source:
172.25.25.18
172.25.25.19

Destination:
172.25.3.194
172.25.3.195
172.25.3.196
172.25.3.197
172.25.3.198

Protocol:
UDP

Port:
6081
```

### 3. Routing

Verify that the route between:

```text
172.25.25.0/?
```

and

```text
172.25.3.0/?
```

is correct in both directions.

### 4. Inter-Zone Security Policy

Compare the security policies between:

```text
Backend ↔ Frontend
```

and:

```text
DMZ ↔ Frontend
```

because Backend/Frontend Cilium communication works while DMZ/Frontend communication does not.

---

## Current Conclusion

The current evidence points to a **network-path problem affecting Cilium Geneve traffic between the DMZ and Frontend zones**.

The strongest evidence is:

1. Cilium is generating UDP 6081 traffic.
2. The UDP 6081 packet is visible leaving the DMZ worker.
3. The corresponding packet is not visible arriving at the Frontend worker.
4. Therefore, the packet is being lost somewhere between the two nodes.
5. The exact device responsible has not yet been identified.
6. ICMP or other successful connections do not prove that UDP 6081 is permitted.
7. TCP 6081 is irrelevant; Geneve requires **UDP 6081**.

### Main Question for the Network Advisor

> **Can you verify the complete network path between the DMZ Kubernetes nodes (`172.25.25.18/19`) and the Frontend Kubernetes nodes (`172.25.3.194–198`), specifically for bidirectional UDP/6081 traffic, and check whether any firewall, ACL, or network security device is dropping the Geneve packets?**
