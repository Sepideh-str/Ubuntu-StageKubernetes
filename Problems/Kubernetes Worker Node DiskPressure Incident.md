# Kubernetes Worker DiskPressure Incident — stage-workerd2

## 1. Summary

On **17 September 2026**, Kubernetes worker node `stage-workerd2` temporarily entered the `DiskPressure` condition during the Argo CD uninstall/reinstall activity.

The kubelet detected pressure on the `ephemeral-storage` resource and attempted to reclaim storage. Shortly afterward, several Argo CD pods were rejected/evicted because the node was under `DiskPressure`.

The condition subsequently cleared, and the node returned to a healthy state.

The investigation also identified that the server has a **60 GB physical disk**, but only **11 GB is currently allocated to the root (`/`) logical volume**. Approximately **11 GB of additional space is available inside the LVM volume group**.

---

## 2. Node Disk Layout

The physical disk is:

```text
sda    60G
```

Partition layout:

```text
sda
├── sda1    1G     /boot/efi
├── sda2    2G     /boot
└── sda3    21.9G  LVM
```

The LVM logical volume currently used for `/` is:

```text
ubuntu--vg-ubuntu--lv    11G    /
```

Therefore, the current storage layout is approximately:

```text
Physical disk:        60 GB
Allocated to sda3:    21.9 GB
Root logical volume:  11 GB
Free inside LVM VG:   ~11 GB
Unallocated disk:     ~38 GB
```

### LVM information

```text
VG        VSize     VFree
ubuntu-vg <21.95g  10.97g
```

Physical volume:

```text
PV         VG        PSize     PFree
/dev/sda3  ubuntu-vg <21.95g  10.97g
```

This means the system already has approximately **10.97 GB of free space inside the LVM volume group**.

---

## 3. Current Root Filesystem Usage

The root filesystem is currently:

```text
Filesystem                         Size  Used  Avail  Use%
/dev/mapper/ubuntu--vg-ubuntu--lv  11G   7.9G  2.4G   78%
```

Therefore:

* Root filesystem size: **11 GB**
* Used: **7.9 GB**
* Available: **2.4 GB**
* Usage: **78%**

Containerd is using approximately:

```text
/var/lib/containerd    2.0G
```

The kubelet directory itself was approximately:

```text
/var/lib/kubelet       1008K
```

---

## 4. Kubelet Evidence

The kubelet log shows that the eviction manager detected pressure specifically related to:

```text
resourceName="ephemeral-storage"
```

At approximately **11:56:29**:

```text
"Eviction manager: attempting to reclaim"
resourceName="ephemeral-storage"
```

The kubelet then attempted to reduce the pressure:

```text
"Eviction manager: able to reduce resource pressure without evicting pods."
resourceName="ephemeral-storage"
```

However, shortly afterward, pods were denied because the node was still considered to be under `DiskPressure`.

At approximately **11:56:31**:

```text
"Pod admission denied"
reason="Evicted"
message="The node had condition: [DiskPressure]."
```

Affected Argo CD workloads included:

```text
argocd-notifications-controller
argocd-application-controller
```

Multiple attempts to create/run the Argo CD application controller were also rejected while the node was under pressure.

---

## 5. Node Condition After the Incident

After the temporary pressure was resolved, the node returned to a healthy state.

Current condition:

```text
DiskPressure    False
Ready           True
```

Therefore, there is currently **no active DiskPressure condition** on `stage-workerd2`.

---

## 6. Relationship to Argo CD Reinstallation

The DiskPressure event occurred during the same period as the Argo CD uninstall/reinstall operation.

The reinstall involved removing the previous Argo CD deployment and creating a new deployment, which can temporarily increase container runtime storage activity through:

* Pulling container images
* Creating container layers
* Starting new containers
* Removing/recreating containers
* Temporary container runtime data

Therefore, the Argo CD reinstall **may have contributed to the temporary increase in ephemeral-storage usage**.

However, the investigation does **not provide enough evidence to state that Argo CD was the root cause** of the DiskPressure condition.

The confirmed sequence is:

```text
Ephemeral-storage pressure
        ↓
Kubelet detects DiskPressure
        ↓
Kubelet attempts storage reclamation
        ↓
Pressure remains temporarily
        ↓
Pods are evicted/rejected
        ↓
Disk pressure clears
        ↓
Node returns to Ready / DiskPressure=False
```

---

## 7. Root Cause vs. Contributing Factor

### Confirmed

The immediate reason for the pod eviction was:

```text
DiskPressure caused by ephemeral-storage pressure
```

This is directly confirmed by the kubelet logs.

### Possible contributing factor

The Argo CD reinstall occurred during the same period and may have temporarily increased container storage usage.

### Infrastructure factor

The root filesystem is only **11 GB**, while the server has a **60 GB physical disk**.

This leaves relatively little filesystem capacity for Kubernetes/containerd workloads even though additional storage is available in the underlying disk/LVM configuration.

---

## 8. Important Finding

The server does **not** have only 11 GB of total disk.

It has:

```text
Physical disk: 60 GB
```

But only:

```text
Root logical volume: 11 GB
```

The LVM volume group currently has approximately:

```text
Free LVM space: 10.97 GB
```

Therefore, the root filesystem can potentially be expanded using the existing LVM capacity without adding another physical disk.

There is also additional unused capacity on the physical disk that has not yet been allocated to `sda3`.

---

## 9. Current Argo CD Status

After switching from Argo CD v3.5.3 to v3.4.3, the current Argo CD components are healthy.

Current workloads:

```text
argocd-application-controller       Running
argocd-applicationset-controller    Running
argocd-notifications-controller     Running
argocd-redis                        Running
argocd-repo-server                  Running
argocd-server                       Running
```

All current pods have:

```text
RESTARTS = 0
```

The previously evicted notification-controller pods were removed after confirming that the node was no longer under disk pressure.

---

## 10. Recommended Action

Before adding additional platform components, review the storage allocation of the Kubernetes worker nodes.

For `stage-workerd2`, the immediate option is to evaluate expanding the root logical volume using the existing **10.97 GB of free LVM space**.

The expansion should **not be performed until the disk/LVM layout of the other Kubernetes nodes is checked**, so that the cluster has a consistent storage strategy.

Useful commands for reviewing the configuration:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

```bash
sudo pvs
```

```bash
sudo vgs
```

```bash
sudo lvs
```

```bash
df -h /
```

No filesystem/LVM changes were performed as part of this investigation.
