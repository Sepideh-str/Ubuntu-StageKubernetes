# APISIX etcd Local Storage Configuration

## 1. Purpose

This document describes the persistent storage prepared for the separate APISIX Develop and Stage environments in the Kubernetes cluster.

Each environment will use a dedicated three-member etcd cluster. Each etcd member will have its own Kubernetes PersistentVolume (PV) backed by a local directory on a frontend worker node.

The storage is prepared before deploying the APISIX Helm releases.

## 2. Storage Architecture

The configuration uses six local PersistentVolumes:

| Environment | etcd member | PersistentVolume | Storage |
|---|---|---|---:|
| Develop | 0 | `apisix-develop-etcd-0-pv` | 2 GiB |
| Develop | 1 | `apisix-develop-etcd-1-pv` | 2 GiB |
| Develop | 2 | `apisix-develop-etcd-2-pv` | 2 GiB |
| Stage | 0 | `apisix-stage-etcd-0-pv` | 2 GiB |
| Stage | 1 | `apisix-stage-etcd-1-pv` | 2 GiB |
| Stage | 2 | `apisix-stage-etcd-2-pv` | 2 GiB |

**Total declared storage:** 12 GiB, with 6 GiB allocated to each environment.

## 3. Worker Placement

The local directories are distributed across the two frontend workers.

| Worker | Local storage directory |
|---|---|
| `stage-workerf1` | `/var/lib/k8s-local-storage/apisix-develop-etcd-0` |
| `stage-workerf1` | `/var/lib/k8s-local-storage/apisix-develop-etcd-1` |
| `stage-workerf1` | `/var/lib/k8s-local-storage/apisix-stage-etcd-0` |
| `stage-workerf2` | `/var/lib/k8s-local-storage/apisix-develop-etcd-2` |
| `stage-workerf2` | `/var/lib/k8s-local-storage/apisix-stage-etcd-1` |
| `stage-workerf2` | `/var/lib/k8s-local-storage/apisix-stage-etcd-2` |

Worker addresses:

- `stage-workerf1`: `172.25.3.197`
- `stage-workerf2`: `172.25.3.198`

The PVs use node affinity with the `kubernetes.io/hostname` label. This ensures that Kubernetes can mount each local volume only on its designated worker.

## 4. PersistentVolume Configuration

Every PV uses the following configuration:

| Setting | Value | Purpose |
|---|---|---|
| `capacity.storage` | `2Gi` | Declared volume capacity |
| `volumeMode` | `Filesystem` | Filesystem-based storage |
| `accessModes` | `ReadWriteOnce` | Read/write mounting from one node at a time |
| `persistentVolumeReclaimPolicy` | `Retain` | Keeps the PV and its data available for manual recovery after a claim is released |
| `storageClassName` | `""` | Disables dynamic storage provisioning for these PVs |
| `local.path` | Environment-specific directory | Identifies the directory on the worker |
| `nodeAffinity` | Specific worker hostname | Restricts the PV to its local node |

The PVs also carry labels:

- `app: apisix-etcd`
- `environment: develop` or `environment: stage`

These labels will allow the corresponding etcd PVCs to select only their own environment's volumes.

**Important:** A PV's declared `2Gi` capacity does not enforce a filesystem quota on the local directory. Actual disk usage must be monitored separately.

## 5. Local Directory Preparation

The local storage root is:

```text
/var/lib/k8s-local-storage
```

The directories were created on the designated frontend workers before the PVs were applied.

The intended directory permissions were set using:

```bash
chown -R 1001:1001 /var/lib/k8s-local-storage/apisix-*
chmod 700 /var/lib/k8s-local-storage/apisix-*
```

These permissions are based on the expected etcd container user and must be checked against the actual image and chart security context before deployment.

## 6. Applying the PV Manifest

The PV definitions are stored on `stage-masterf1` at:

```text
/root/apisix-etcd-pv.yaml
```

Validate the manifest without creating resources:

```bash
kubectl apply --dry-run=client -f /root/apisix-etcd-pv.yaml
```

Create the PVs:

```bash
kubectl apply -f /root/apisix-etcd-pv.yaml
```

Verify their status:

```bash
kubectl get pv
```

Expected result: six PVs with `CAPACITY` set to `2Gi` and `STATUS` set to `Available`, until their PVCs are created and bound.

For a compact view:

```bash
kubectl get pv \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.spec.capacity.storage,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
```

## 7. Environment Isolation

The Develop etcd release must claim only PVs labelled:

```yaml
environment: develop
```

The Stage etcd release must claim only PVs labelled:

```yaml
environment: stage
```

The etcd Helm values must configure persistent storage, a `2Gi` claim size, an empty storage class, and the appropriate PV selector.

For example, the relevant Develop settings are expected to follow this structure:

```yaml
persistence:
  enabled: true
  storageClass: ""
  accessModes:
    - ReadWriteOnce
  size: 2Gi
  selector:
    matchLabels:
      environment: develop
      app: apisix-etcd
```

The equivalent Stage configuration uses `environment: stage`.

These settings must be validated against the installed chart's templates before deployment.

## 8. Operational Considerations

### Worker failure

The three etcd members of each environment are distributed over two workers, not three independent failure domains.

If a worker hosting two members becomes unavailable, the corresponding etcd cluster may lose quorum. Local PVs do not automatically move their data to another node.

### Data retention

The PV reclaim policy is `Retain`. Deleting a PVC does not mean the underlying local data has been safely removed. Data cleanup or reuse should be a deliberate administrative operation.

### Storage capacity

The `2Gi` value is a Kubernetes declaration, not a hard directory limit. Monitor the worker filesystems and etcd database growth.

### Backups

Local PVs are not backups. Establish and test an etcd snapshot and recovery procedure before relying on these clusters for important API configuration.

## 9. Current Status

The six PVs have been created and were reported as `Available`.

The following items are not yet complete:

- Develop etcd PVC creation and binding
- Stage etcd PVC creation and binding
- APISIX gateway deployment for each environment
- Ingress-controller deployment for each environment
- Validation of etcd cluster health and persistence after pod restart
- Snapshot and recovery testing

The existing Cilium shared Gateway remains the cluster's external entry point and is not changed by this storage configuration.
