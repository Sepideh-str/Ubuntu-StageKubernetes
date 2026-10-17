# Kubernetes / Argo CD Installation Issues — Summary

## 1. Argo CD v3.5.3 Issue

During the initial Argo CD installation, we deployed:

* Argo CD: **v3.5.3**
* Helm chart: **10.9.1**
* Kubernetes: **v1.36.4**

The `argocd-repo-server` repeatedly failed its liveness check:

```text
/healthz?full=true
```

Kubernetes reported:

```text
context deadline exceeded
Client.Timeout exceeded while awaiting headers
```

Increasing the liveness probe timeout from **1 second to 10 seconds** did not resolve the problem.

Manual testing showed:

```text
/healthz
→ 200 OK
```

but:

```text
/healthz?full=true
→ Empty reply from server
```

The repo-server logs also showed health-check requests being cancelled after approximately 5 seconds.

### Resolution

We removed Argo CD v3.5.3 and installed the same version used by our other working cluster:

* Argo CD: **v3.4.3**
* Helm chart: **9.5.21**

With v3.4.3, the repo-server remained healthy and successfully handled its internal gRPC health checks.

**Conclusion:** The evidence strongly indicates that the repo-server health-check problem was specific to **Argo CD v3.5.3 in our environment**. We did not identify the exact internal cause of the v3.5.3 behavior.

---

## 2. DiskPressure / Pod Eviction

During the Argo CD reinstall, `stage-workerd2` temporarily entered:

```text
DiskPressure = True
```

Kubelet logs confirmed that the pressure was related to:

```text
ephemeral-storage
```

The kubelet attempted to reclaim storage, but several Argo CD pods were subsequently evicted/rejected.

Affected workloads included:

```text
argocd-notifications-controller
argocd-application-controller
```

The node later recovered:

```text
DiskPressure = False
Ready = True
```

The evicted pods were removed, and the replacement Argo CD pods are currently healthy.

---

## 3. Disk Investigation

The physical disk on `stage-workerd2` is:

```text
60 GB
```

However, the root filesystem is only:

```text
11 GB
```

Current usage:

```text
11 GB total
7.9 GB used
2.4 GB available
78% used
```

Containerd uses approximately:

```text
2.0 GB
```

The important finding is that the server does **not** have only an 11 GB disk.

The current LVM configuration is approximately:

```text
Physical disk:       60 GB
LVM partition:       21.9 GB
Root logical volume: 11 GB
Free LVM space:      ~11 GB
```

Therefore, approximately **11 GB is already available inside the LVM volume group** and could potentially be allocated to the root filesystem.

There is also additional unused space on the physical disk that has not yet been allocated to the LVM partition.

---

## 4. Overall Conclusion

Two separate issues were observed:

### Argo CD

Argo CD **v3.5.3** had a repo-server health-check problem. Switching to **v3.4.3** resolved the issue in the current environment.

### Node Storage

`stage-workerd2` experienced temporary `DiskPressure` caused by `ephemeral-storage` pressure. The Argo CD reinstall may have contributed to temporary storage activity, but the investigation does **not prove that Argo CD was the root cause**.

The underlying infrastructure has a **60 GB disk**, but only **11 GB is currently allocated to `/`**, which provides limited working space for Kubernetes/containerd workloads.

### Recommended Action

Review and standardize the storage allocation of the Kubernetes worker nodes before deploying additional platform components.

No filesystem or LVM resizing was performed during this investigation.
