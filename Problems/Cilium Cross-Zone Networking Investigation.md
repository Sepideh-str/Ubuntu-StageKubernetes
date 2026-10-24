# Cilium Cross-Zone Networking Investigation

## 1. Problem Summary

The Kubernetes cluster has separate network zones:

* FRONTEND
* BACKEND
* DMZ

The current problem is that **Kubernetes pod-to-pod networking through Cilium is not working correctly between FRONTEND and DMZ**.

The node-to-node network itself is working, but traffic between Kubernetes Pod networks across the zones is failing.

This issue also affects Argo CD because the Argo CD Repository Server is running in FRONTEND while one of the CoreDNS pods is running in DMZ.

---

# 2. Kubernetes Network Architecture

The relevant nodes are:

| Zone     | Node     | Node IP        |
| -------- | -------- | -------------- |
| FRONTEND | WorkerF2 | `172.25.3.198` |
| DMZ      | WorkerD2 | `172.25.25.19` |

The relevant Kubernetes Pods are:

| Component           | Pod IP       | Node     |
| ------------------- | ------------ | -------- |
| Argo CD Repo Server | `10.0.4.245` | WorkerF2 |
| CoreDNS             | `10.0.4.141` | WorkerF2 |
| CoreDNS             | `10.0.8.143` | WorkerD2 |

Cilium uses **Geneve** as the pod-network tunneling protocol.

The Geneve transport uses:

```text
UDP 6081
```

---

# 3. Important Network Layers

There are two different network layers involved.

## 3.1 Node Network

This is the normal network between Kubernetes nodes.

Example:

```text
WorkerF2
172.25.3.198
        |
        | ICMP
        |
        v
WorkerD2
172.25.25.19
```

We tested this connection and it works.

## 3.2 Kubernetes Pod Network

Kubernetes Pods use Cilium networking.

For example:

```text
Pod on WorkerF2
10.0.4.x
        |
        | Cilium Geneve
        | UDP 6081
        |
        v
Pod on WorkerD2
10.0.8.x
```

This is the network path that is currently failing.

---

# 4. Test 1 — Node-to-Node Connectivity

From WorkerF2:

```bash
ping -c 3 172.25.25.19
```

Result:

```text
3 packets transmitted, 3 received, 0% packet loss
rtt min/avg/max/mdev = 1.088/1.181/1.283/0.079 ms
```

This proves:

```text
WorkerF2
172.25.3.198
      |
      | ICMP works
      |
      v
WorkerD2
172.25.25.19
```

Therefore, the basic IP connectivity between the two nodes exists.

However, this test does **not** prove that Cilium's Geneve traffic is working.

---

# 5. Test 2 — Cilium Geneve Traffic

On WorkerF2 we started:

```bash
tcpdump -ni any host 172.25.25.19 and udp port 6081
```

Then we tested connectivity to the CoreDNS Pod on WorkerD2:

```bash
ping -c 3 10.0.8.143
```

The ping failed:

```text
3 packets transmitted, 0 received, 100% packet loss
```

At the same time, tcpdump showed Geneve packets being sent:

```text
172.25.3.198 → 172.25.25.19:6081
Geneve
```

For example:

```text
12:06:28.506838 ens33 Out IP
172.25.3.198.17211 > 172.25.25.19.6081:
Geneve, Flags [none], vni 0x6:
IP 10.0.4.8 > 10.0.8.143:
ICMP echo request
```

This is important.

It shows that Cilium is encapsulating the Pod traffic inside Geneve and attempting to send it to WorkerD2.

The traffic path is therefore:

```text
Pod
10.0.4.8
   |
   | ICMP
   v
Cilium
   |
   | Geneve UDP 6081
   v
WorkerD2
172.25.25.19
   |
   | should deliver
   v
Pod
10.0.8.143
```

But no response was received.

---

# 6. What We Have Proven

At this point we have strong evidence for the following:

## Node network works

```text
FRONTEND node
172.25.3.198
       |
       | ICMP
       | WORKS
       v
DMZ node
172.25.25.19
```

## Cilium Pod network fails

```text
FRONTEND Pod
10.0.4.x
       |
       | Geneve UDP 6081
       | FAILING
       v
DMZ Pod
10.0.8.x
```

Therefore:

> The problem is not simply basic IP connectivity between the FRONTEND and DMZ nodes.

The problem is specifically related to the **Cilium Pod networking path between the zones**.

---

# 7. Cilium Health Evidence

Cilium also reports problems reaching the DMZ nodes.

Cilium status showed:

```text
Cluster health: 7/9 reachable
```

The DMZ nodes were reported as unreachable:

```text
stage-workerd1   172.25.25.18   1/1   0/1
stage-workerd2   172.25.25.19   1/1   0/1
```

This is consistent with the connectivity tests.

The Cilium agents are running, but Cilium's cross-node health communication with the DMZ nodes is not succeeding.

---

# 8. Why This Affects Argo CD

The Argo CD Repository Server is running on WorkerF2:

```text
argocd-repo-server
Pod IP: 10.0.4.245
Node: WorkerF2
Zone: FRONTEND
```

The Kubernetes DNS Service is:

```text
kube-dns
ClusterIP: 10.96.0.10
Port: 53
```

There are two CoreDNS Pods:

```text
CoreDNS
10.0.4.141
WorkerF2
FRONTEND
```

and:

```text
CoreDNS
10.0.8.143
WorkerD2
DMZ
```

Therefore, the logical DNS path can be:

```text
Argo CD Repo Server
10.0.4.245
        |
        v
kube-dns Service
10.96.0.10:53
        |
        v
CoreDNS
10.0.8.143
        |
        X
   Cilium path
   FRONTEND → DMZ
```

If the Kubernetes DNS Service selects the CoreDNS endpoint on WorkerD2, the request requires working Cilium connectivity between FRONTEND and DMZ.

---

# 9. Argo CD Error

Argo CD is trying to access the GitLab repository:

```text
https://git.crouseco.com/software/k8s/helm.git
```

The Repository Server reported:

```text
dial tcp:
lookup git.crouseco.com on 10.96.0.10:53:
read udp 10.0.4.245:50247->10.96.0.10:53:
i/o timeout
```

This is significant because the error occurs while performing DNS resolution.

The Repository Server is trying to use:

```text
10.96.0.10:53
```

which is the Kubernetes DNS Service.

Therefore, the Argo CD Git connection problem can be explained by the underlying Kubernetes DNS/network connectivity problem.

---

# 10. Important Observation

The GitLab server itself is not necessarily the problem.

From the WorkerF2 host, DNS and HTTPS connectivity to GitLab work.

The browser can also reach:

```text
https://git.crouseco.com
```

However, the Argo CD Repository Server is a Kubernetes Pod.

Its network path is different:

```text
Argo CD Pod
10.0.4.245
      |
      v
Kubernetes DNS
10.96.0.10
      |
      v
CoreDNS Pod
      |
      v
GitLab
172.25.2.242
```

Therefore, testing GitLab from the Kubernetes node does not completely prove that the Argo CD Pod can reach GitLab.

---

# 11. Current Root Cause Area

The current investigation points to:

```text
Cilium cross-zone Pod networking
```

Specifically:

```text
FRONTEND → DMZ
```

The evidence shows:

1. Node-to-node ICMP works.
2. Cilium uses Geneve UDP 6081.
3. Cilium sends Geneve traffic from FRONTEND toward DMZ.
4. Pod-to-Pod traffic does not receive a response.
5. Cilium health reports the DMZ nodes as unreachable.
6. One CoreDNS endpoint is located in DMZ.
7. Argo CD Repository Server is located in FRONTEND.
8. Argo CD experiences Kubernetes DNS timeouts.

---

# 12. What Is Not Proven Yet

We should not yet state that the firewall is definitely the root cause.

Possible causes still include:

* Firewall filtering UDP 6081
* Return traffic for UDP 6081 being blocked
* Routing problems for Geneve traffic
* Cilium configuration differences between zones
* MTU problems
* Network device handling of Geneve traffic
* Problems with the Cilium agent on DMZ nodes
* Other infrastructure-level filtering

The next investigation should determine exactly where the Geneve packet is lost.

---

# 13. What We Should Ask the Network Team

The most useful information for the network team is:

```text
FRONTEND node:
172.25.3.198

DMZ node:
172.25.25.19

Protocol:
UDP

Destination port:
6081

Purpose:
Cilium Geneve tunnel
```

The question is:

> Can you verify that UDP/6081 traffic is allowed bidirectionally between the FRONTEND Kubernetes nodes and the DMZ Kubernetes nodes, including the return traffic?

For example:

```text
172.25.3.198 → 172.25.25.19 UDP/6081
172.25.25.19 → 172.25.3.198 UDP/6081
```

The same verification should eventually be performed for all Kubernetes nodes that communicate through Cilium.

---

# 14. Current Conclusion

The current investigation has identified a **cross-zone Cilium networking problem**.

The important distinction is:

```text
Node network:

FRONTEND ─────────────── DMZ
             WORKS


Cilium Pod network:

FRONTEND Pod ── Geneve ──X── DMZ Pod
                         FAILS
```

This problem is significant because Kubernetes services such as DNS depend on Pod networking.

In the current cluster, CoreDNS is distributed across FRONTEND and DMZ. Therefore, a Pod in FRONTEND may need to communicate with a CoreDNS Pod in DMZ.

The observed Cilium networking failure can therefore result in DNS timeouts for workloads such as Argo CD.

The next step is to identify exactly where the Geneve UDP/6081 traffic or its return traffic is being lost.

---

# 15. Short Explanation for the Adviser

The Kubernetes nodes in the FRONTEND and DMZ zones can communicate at the normal IP network level. However, Kubernetes Pod-to-Pod communication between these zones is failing through Cilium's Geneve overlay network. We confirmed that Cilium sends Geneve UDP/6081 traffic from the FRONTEND node toward the DMZ node, but the Pod traffic receives no response. Cilium health also reports the DMZ nodes as unreachable. One CoreDNS Pod is located in the DMZ, while the Argo CD Repository Server is located in the FRONTEND. Because Kubernetes DNS uses the CoreDNS Pods through the `kube-dns` Service, the cross-zone Cilium failure can cause DNS requests from Argo CD to time out. The current evidence identifies the Cilium cross-zone networking path as the area of failure; the exact cause, such as firewall filtering, return-path filtering, routing, MTU, or Cilium configuration, still needs to be determined.
# 16. CoreDNS Cross-Zone Validation

To further validate whether the Cilium cross-zone networking problem was responsible for the Argo CD DNS timeout, CoreDNS was temporarily moved from the DMZ to the FRONTEND zone.

Originally, CoreDNS was distributed as:

```text
CoreDNS
10.0.4.141
WorkerF2
FRONTEND
```

and:

```text
CoreDNS
10.0.8.143
WorkerD2
DMZ
```

The Argo CD Repository Server was running in FRONTEND:

```text
argocd-repo-server
10.0.4.245
WorkerF2
FRONTEND
```

Therefore, when the Kubernetes DNS Service selected the CoreDNS Pod in DMZ, the DNS request required cross-zone Cilium communication:

```text
Argo CD Repo Server
10.0.4.245
        |
        | DNS
        v
kube-dns Service
10.96.0.10
        |
        v
CoreDNS
10.0.8.143
        |
        | FRONTEND → DMZ
        | Cilium Geneve
        | UDP 6081
        X
```

## Temporary Validation

CoreDNS was temporarily scheduled only on FRONTEND nodes.

After moving CoreDNS to FRONTEND, the Argo CD Repository Server no longer produced the previous DNS timeout:

```text
lookup git.crouseco.com on 10.96.0.10:53:
read udp ... -> 10.96.0.10:53:
i/o timeout
```

Instead, the error changed to:

```text
tls: failed to verify certificate:
x509: certificate signed by unknown authority
```

This change is significant.

The TLS error means that the request progressed beyond the previous DNS/network timeout and reached the GitLab HTTPS endpoint far enough for TLS certificate validation to occur.

The simplified path became:

```text
Argo CD Repo Server
10.0.4.245
        |
        v
kube-dns
10.96.0.10
        |
        v
CoreDNS
FRONTEND
        |
        v
GitLab
172.25.2.242:443
        |
        v
TLS certificate validation
```

This provides strong additional evidence that the original Argo CD DNS timeout was related to the cross-zone Pod networking path to the CoreDNS Pod running in DMZ.

---

# 17. CoreDNS Finding

The CoreDNS test does **not** prove that CoreDNS itself is faulty.

Instead, the behavior is consistent with the following:

```text
CoreDNS in FRONTEND
        |
        | same-zone Pod communication
        v
Argo CD
        |
        | DNS works far enough
        v
GitLab HTTPS
        |
        X
TLS certificate trust issue
```

Compared with:

```text
CoreDNS in DMZ
        |
        | cross-zone Pod communication
        |
        X
Cilium FRONTEND → DMZ path
        |
        v
DNS timeout
```

Therefore, CoreDNS placement provided an additional validation of the Cilium cross-zone networking issue.

The important conclusion is:

> Moving CoreDNS from DMZ to FRONTEND changed the Argo CD failure from a Kubernetes DNS timeout to a GitLab TLS certificate validation error. This demonstrates that the original DNS timeout was strongly associated with the cross-zone Pod networking path between FRONTEND and DMZ.

This also explains why the node-level tests were misleading: the nodes themselves can communicate successfully, while the Kubernetes Pod network between those nodes can still fail.

---

# 18. Combined Evidence

The investigation now provides multiple independent pieces of evidence:

1. **Node-to-node connectivity works**

```text
172.25.3.198 → 172.25.25.19
ICMP: SUCCESS
```

2. **Cilium attempts to send Geneve traffic**

```text
172.25.3.198 → 172.25.25.19
UDP/6081
Geneve: OBSERVED
```

3. **Pod-to-Pod communication fails**

```text
10.0.4.x → 10.0.8.x
Pod traffic: FAIL
```

4. **Cilium health reports DMZ nodes as unreachable**

```text
stage-workerd1  0/1
stage-workerd2  0/1
```

5. **Argo CD DNS requests time out when CoreDNS can be selected in DMZ**

```text
10.0.4.245 → 10.96.0.10:53
DNS: TIMEOUT
```

6. **Moving CoreDNS to FRONTEND changes the failure**

```text
DNS timeout
      ↓
TLS certificate validation error
```

Taken together, these observations strongly support the conclusion that the **FRONTEND ↔ DMZ Cilium Pod networking path is the primary area requiring investigation**.

The exact infrastructure cause is still not proven and may involve UDP/6081 filtering, return traffic, routing, MTU, network-device handling of Geneve, or Cilium/node configuration.
