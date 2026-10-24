# HAProxy and Kubernetes Control Plane HA Preparation

## Overview

The Kubernetes cluster uses three control-plane nodes with a highly available API endpoint.

HAProxy provides load balancing for Kubernetes API traffic, while Corosync and Pacemaker provide cluster management and resource failover.

### Architecture

```text
                 Kubernetes API VIP
                  <VIP>:7443
                       |
                    HAProxy
                  /    |    \
                 /     |     \
           Master 1  Master 2  Master 3
             :6443     :6443     :6443
                 \      |      /
                  Corosync
                     |
                  Pacemaker
                     |
                     PCS
```

## HAProxy Installation

Install HAProxy on each control-plane node:

```bash
sudo apt update
sudo apt install -y haproxy
```

Verify:

```bash
haproxy -v
```

Configure:

```text
vi  /etc/haproxy/haproxy.cfg
```

Kubernetes API configuration:

```text
#---------------------------------------------------------------------
# Kubernetes
#---------------------------------------------------------------------
frontend kubernetes
    bind *:7443
    mode tcp
    option tcplog
    default_backend kubernetes-master-nodes

backend kubernetes-master-nodes
    mode tcp
    balance roundrobin

    server master1 172.25.3.194:6443 check
    server master2 172.25.3.195:6443 check
    server master3 172.25.3.196:6443 check
```

Validate and enable HAProxy:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

Verify:

```bash
sudo systemctl status haproxy
sudo ss -lntp | grep 7443
```

At this stage the backend servers may appear DOWN because the Kubernetes API servers have not been initialized yet. This is expected.

## Pacemaker, Corosync and PCS

Install the HA components from the configured Ubuntu repositories:

```bash
sudo apt install -y pacemaker corosync pcs
```

Enable PCS:

```bash
sudo systemctl enable pcsd
sudo systemctl start pcsd
```

Verify:

```bash
sudo systemctl status pcsd
```

Set the `hacluster` password:

```bash
sudo passwd hacluster
```

The same password must be configured on all three control-plane nodes.

## Components

* **Corosync** — provides cluster communication and node membership.
* **Pacemaker** — manages HA resources and failover.
* **PCS** — command-line management interface for the HA cluster.
* **HAProxy** — load-balances Kubernetes API traffic.
* **VIP** — provides a stable endpoint for the Kubernetes API.

The HA cluster will be configured after all three control-plane nodes have the required packages and services installed.
