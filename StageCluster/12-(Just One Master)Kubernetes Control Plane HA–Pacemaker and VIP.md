# Kubernetes Control Plane HA – Pacemaker and VIP

## Overview

The Kubernetes control plane uses three master nodes for high availability.

Pacemaker and Corosync provide the infrastructure-level HA layer, while a Virtual IP (VIP) provides a single stable endpoint for the Kubernetes API.

```text
                    Kubernetes API VIP
                       172.25.3.199
                              │
                     ┌────────▼────────┐
                     │   Pacemaker     │
                     │  VIP Management │
                     └────────┬────────┘
                              │
             ┌────────────────┼────────────────┐
             │                │                │
        Master-F1        Master-F2        Master-F3
        172.25.3.194     172.25.3.195     172.25.3.196
             │                │                │
          HAProxy           HAProxy          HAProxy
             │                │                │
             └────────────────┼────────────────┘
                              │
                       Kubernetes API
                          TCP 6443
```

## 1. Create the Pacemaker Cluster

Three master nodes are configured as a Corosync/Pacemaker cluster.

```bash
pcs host auth Stage-MasterF1 Stage-MasterF2 Stage-MasterF3 -u hacluster

pcs cluster setup kubernetes-ha \
    Stage-MasterF1 \
    Stage-MasterF2 \
    Stage-MasterF3

pcs cluster start --all
pcs cluster enable --all
```

Verify:

```bash
pcs status
```

Expected:

```text
3 nodes configured
Online: [ Stage-MasterF1 Stage-MasterF2 Stage-MasterF3 ]
```

## 2. Configure Cluster Properties

For this Kubernetes HA environment:

```bash
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
```

Verify:

```bash
pcs property config
```

> **Note:** STONITH/fencing is disabled for this environment. A production implementation should evaluate proper fencing rather than relying on this configuration.

## 3. Create the Kubernetes API VIP

The Kubernetes API uses a shared Virtual IP:

```text
172.25.3.199
```

The VIP is managed by Pacemaker using the `IPaddr2` resource:

```bash
pcs resource create kube-vip ocf:heartbeat:IPaddr2 \
    ip=172.25.3.199 \
    cidr_netmask=28 \
    nic=ens33 \
    op monitor interval=30s
```

Verify:

```bash
pcs status
```

Expected:

```text
Full List of Resources:
  * kube-vip (ocf:heartbeat:IPaddr2): Started Stage-MasterF1
```

The node shown after `Started` is the node currently owning the VIP.

## 4. Understanding the VIP

The VIP is **not a separate server**.

It is an additional IPv4 address temporarily assigned to the network interface of the active master.

For example, on Master-F1:

```text
inet 172.25.3.194/28
inet 172.25.3.199/28 secondary
```

This means:

```text
172.25.3.194  → Master-F1's normal IP
172.25.3.199  → Shared Kubernetes API VIP
```

The `secondary` keyword means that `.199` is an additional IP address on the same interface.

If Master-F1 fails, Pacemaker removes the VIP from Master-F1 and assigns it to another master:

```text
Master-F1
  172.25.3.194
  ~~ 172.25.3.199 ~~   ← VIP removed

Master-F2
  172.25.3.195
  172.25.3.199        ← VIP moved here
```

Applications and Kubernetes clients continue using:

```text
172.25.3.199:7443
```

They do not need to know which master currently owns the VIP.

## 5. Why the VIP Is Required

Without a VIP, clients would need to know individual control-plane addresses:

```text
Master-F1:6443
Master-F2:6443
Master-F3:6443
```

With the VIP, there is one stable endpoint:

```text
172.25.3.199:7443
```

HAProxy then forwards the connection to an available Kubernetes API server on port `6443`.

Therefore the overall path is:

```text
Kubernetes Client
       │
       ▼
172.25.3.199:7443
       │
       ▼
   HAProxy
       │
       ├── Master-F1:6443
       ├── Master-F2:6443
       └── Master-F3:6443
```

## 6. Verification

Check the cluster:

```bash
pcs status
```

Check the VIP:

```bash
ip addr show ens33
```

The active master should show:

```text
inet 172.25.3.199/28 secondary
```

Test VIP connectivity from another master:

```bash
ping -c 3 172.25.3.199
```

The VIP should move to another master if the current owner becomes unavailable.

## Result

The infrastructure HA layer is now prepared:

```text
Corosync
    │
    ▼
Pacemaker
    │
    ▼
Kubernetes API VIP
172.25.3.199
    │
    ▼
HAProxy :7443
    │
    ▼
Kubernetes API Servers :6443
```

The Kubernetes cluster can now use the VIP as its stable control-plane endpoint.
