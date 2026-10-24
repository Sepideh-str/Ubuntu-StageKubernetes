# APISIX Stage Deployment

## 1. Purpose

This document describes the deployment of Apache APISIX for the Stage environment in the Kubernetes cluster.

The Stage installation is independent of the Develop installation. Each environment has its own namespace, Helm release, APISIX gateway, ingress controller, etcd cluster, administrator credentials, and persistent volumes.

The existing Cilium `shared-gateway` remains the cluster's external entry point. APISIX provides API management behind that entry point.

## 2. Deployment Overview

| Component | Stage configuration |
|---|---|
| Kubernetes namespace | `apisix-stage` |
| Helm release | `apisix-stage` |
| Helm chart | APISIX `2.18.0` |
| APISIX image version | `3.19.0-ubuntu` |
| APISIX replicas | 2 |
| Ingress controller image version | `2.2.0` |
| Ingress controller replicas | 2 |
| ADC image version | `0.27.1` |
| etcd replicas | 3 |
| etcd storage per replica | 2 GiB |
| IngressClass | `apisix-stage` |
| APISIX admin service | `apisix-stage-admin:9180` |
| Admin credentials Secret | `apisix-admin-credentials` |
| IPv6 | Disabled |
| Node placement | Frontend workers |
| Image registry | `repository.crouseco.com` |

All application images are configured to use the internal Nexus registry.

## 3. Resource Isolation

Stage resources are deployed in the `apisix-stage` namespace.

The following resources are specific to Stage:

- APISIX gateway Deployment
- APISIX ingress controller Deployment
- Three-member etcd cluster
- APISIX admin Service
- GatewayProxy configuration
- Admin credentials Secret
- etcd PVCs

The Develop installation remains in `apisix-develop`.

The Stage ingress controller uses `IngressClass/apisix-stage`, while Develop retains `IngressClass/apisix`. This distinction is necessary because Kubernetes IngressClass resources are cluster-scoped and cannot be owned by two independent Helm releases under the same name.

## 4. Configuration Files

The local Helm chart and Stage configuration are stored on the Kubernetes master:

```text
/root/apisix/
/root/apisix/values-stage.yaml
/root/apisix/rendered-stage.yaml
```

- `values-stage.yaml` contains the Stage deployment configuration.
- `rendered-stage.yaml` contains the rendered Kubernetes manifests for inspection.

The Helm release is installed from the local chart rather than directly from a public chart repository.

### Important values

The Stage values file includes the following configuration:

```yaml
replicaCount: 2

nodeSelector:
  zone: frontend

service:
  type: ClusterIP
  
apisix:
  enableIPv6: false
  admin:
    enabled: true
    enable_admin_ui: false
    type: ClusterIP
    credentials:
      secretName: apisix-admin-credentials
      secretAdminKey: admin
      secretViewerKey: viewer

etcd:
  enabled: true
  replicaCount: 3
  persistence:
    enabled: true
    storageClass: "-"
    accessModes:
      - ReadWriteOnce
    size: 2Gi
    selector:
      matchLabels:
        app: apisix-etcd
        environment: stage

ingress-controller:
  enabled: true
  webhook:
    enabled: false
  deployment:
    replicas: 2
  config:
    controllerName: apisix.apache.org/apisix-ingress-controller
    disableGatewayAPI: false
    kubernetes:
      ingressClass: apisix-stage
```

These are selected values, not the complete Helm values file. Use `/root/apisix/values-stage.yaml` as the authoritative deployment configuration.

## 5. Credentials

The Stage admin credentials are stored in a Kubernetes Secret:

```text
Namespace: apisix-stage
Secret:    apisix-admin-credentials
Keys:      admin, viewer
```

The keys were generated independently using random hexadecimal values.

The GatewayProxy references the admin key through `secretKeyRef` instead of embedding the credential in the manifest.

Verify the Secret without exposing its values:

```bash
kubectl get secret apisix-admin-credentials \
  -n apisix-stage \
  -o go-template='Name: {{.metadata.name}}{{"\n"}}Type: {{.type}}{{"\n"}}Keys:{{range $k, $v := .data}} {{$k}}{{end}}{{"\n"}}'
```

Do not include credential values in Git, documentation, terminal transcripts, or troubleshooting reports. Kubernetes Secrets are not encrypted merely because they are stored as Secret resources; appropriate encryption at rest and RBAC restrictions should be configured.

## 6. Persistent Storage

Stage uses three pre-created local PersistentVolumes for etcd.

| PersistentVolume | Capacity | Assigned worker | Host path |
|---|---|---|---|
| `apisix-stage-etcd-0-pv` | 2 GiB | `stage-workerf1` | `/var/lib/k8s-local-storage/apisix-stage-etcd-0` |
| `apisix-stage-etcd-1-pv` | 2 GiB | `stage-workerf2` | `/var/lib/k8s-local-storage/apisix-stage-etcd-1` |
| `apisix-stage-etcd-2-pv` | 2 GiB | `stage-workerf2` | `/var/lib/k8s-local-storage/apisix-stage-etcd-2` |

The volumes use the following properties:

- Access mode: `ReadWriteOnce`
- Reclaim policy: `Retain`
- Storage class: empty (`storageClassName: ""`)
- Capacity: `2Gi` per volume
- Selector labels: `app=apisix-etcd`, `environment=stage`

The `environment: stage` selector prevents Stage etcd PVCs from binding to Develop volumes.

### Storage verification

```bash
kubectl get pv \
  -l app=apisix-etcd,environment=stage
```

After installation, the Stage PVCs should be bound to the corresponding Stage PVs:

```bash
kubectl get pvc -n apisix-stage
```

**Availability consideration:** Two of the three etcd members are assigned to `stage-workerf2`. If that worker becomes unavailable, two etcd members may be lost, preventing the cluster from maintaining etcd quorum. Review the placement if higher availability is required.

## 7. Installation Procedure

### Step 1: Create the namespace

```bash
kubectl create namespace apisix-stage
```

If the namespace already exists, verify it instead:

```bash
kubectl get namespace apisix-stage
```

### Step 2: Create credentials

Generate independent Stage credentials and create the Secret:

```bash
set +x

ADMIN_KEY="$(openssl rand -hex 32)"
VIEWER_KEY="$(openssl rand -hex 32)"

kubectl create secret generic apisix-admin-credentials \
  --namespace apisix-stage \
  --from-literal=admin="$ADMIN_KEY" \
  --from-literal=viewer="$VIEWER_KEY"

unset ADMIN_KEY VIEWER_KEY
```

If the Secret already exists, verify it instead of recreating it.

### Step 3: Verify persistent volumes

```bash
kubectl get pv \
  -l app=apisix-etcd,environment=stage
```

Confirm that all three expected PVs exist and are available before installation.

### Step 4: Validate the Helm chart

```bash
helm lint /root/apisix \
  -f /root/apisix/values-stage.yaml
```

Expected result:

```text
1 chart(s) linted, 0 chart(s) failed
```

### Step 5: Render the manifests

```bash
helm template apisix-stage /root/apisix \
  --namespace apisix-stage \
  -f /root/apisix/values-stage.yaml \
  > /root/apisix/rendered-stage.yaml
```

Verify the IngressClass:

```bash
grep -n -A 10 'kind: IngressClass' \
  /root/apisix/rendered-stage.yaml
```

The resource should be named `apisix-stage`, and its GatewayProxy reference should point to `apisix-stage-config` in the `apisix-stage` namespace.

### Step 6: Install the release

```bash
helm install apisix-stage /root/apisix \
  --namespace apisix-stage \
  -f /root/apisix/values-stage.yaml
```

If the release is already installed, inspect it with `helm status` instead of repeating the installation command.

## 8. Post-Installation Verification

### Helm release

```bash
helm status apisix-stage -n apisix-stage
```

### Pods

```bash
kubectl get pods -n apisix-stage -o wide
```

Expected workload counts:

- 2 APISIX gateway pods
- 2 ingress controller pods, each expected to contain two containers
- 3 etcd pods

All containers should become Ready, and the etcd pods should reach `Running`.

### Services

```bash
kubectl get svc -n apisix-stage
```

Confirm the APISIX admin Service is named `apisix-stage-admin` and uses port `9180`.

### Persistent volume claims

```bash
kubectl get pvc -n apisix-stage
```

All three etcd PVCs should be `Bound`.

### IngressClass

```bash
kubectl get ingressclass apisix-stage -o yaml
```

Confirm that the class references:

```text
GatewayProxy: apisix-stage-config
Namespace:   apisix-stage
```

### GatewayProxy

```bash
kubectl get gatewayproxy -n apisix-stage
```

Inspect its configuration:

```bash
kubectl get gatewayproxy apisix-stage-config \
  -n apisix-stage -o yaml
```

The controller's configuration should reference `apisix-stage-admin:9180` and the `admin` key in `apisix-admin-credentials`.

### Events

If a pod is not ready:

```bash
kubectl get events -n apisix-stage \
  --sort-by=.metadata.creationTimestamp
```

Inspect an affected pod:

```bash
kubectl describe pod <pod-name> -n apisix-stage
```

Replace `<pod-name>` with the actual pod name.

## 9. Troubleshooting: IngressClass Ownership Conflict

### Symptom

Helm reports an installation failure similar to:

```text
IngressClass "apisix" exists and cannot be imported
into the current release
```

The error identifies `apisix-develop` as the existing owner.

### Cause

`IngressClass` is a cluster-scoped resource. Both the Develop and Stage releases initially attempted to create a resource named `apisix`, resulting in a Helm ownership conflict.

### Resolution

The Stage configuration was updated to use a separate class:

```yaml
ingress-controller:
  config:
    kubernetes:
      ingressClass: apisix-stage
```

The manifests were rendered again, and the generated IngressClass was verified to be named `apisix-stage`.

Do not delete the Develop-owned IngressClass or manually change its Helm ownership annotations to work around this conflict.

## 10. Operational Commands

| Task | Command |
|---|---|
| Check release | `helm status apisix-stage -n apisix-stage` |
| List pods | `kubectl get pods -n apisix-stage -o wide` |
| List services | `kubectl get svc -n apisix-stage` |
| List PVCs | `kubectl get pvc -n apisix-stage` |
| View events | `kubectl get events -n apisix-stage --sort-by=.metadata.creationTimestamp` |
| View release values | `helm get values apisix-stage -n apisix-stage` |
| View release manifest | `helm get manifest apisix-stage -n apisix-stage` |
| Check Develop isolation | `helm status apisix-develop -n apisix-develop` |

## 11. Routing Integration

The intended external request path is:

```text
Client
  |
  v
Existing Cilium shared-gateway
  |
  v
Stage routing configuration
  |
  v
APISIX Stage gateway
  |
  v
Backend API services
```

The Stage APISIX installation does not, by itself, configure public DNS, attach a route to the shared Cilium Gateway, or prove end-to-end API access. Those items must be verified separately.

Before enabling public Stage traffic, confirm the intended Gateway API `HTTPRoute`, its parent Gateway, hostname, service backend, DNS, and TLS configuration. Keep routing changes in Git and manage them through Argo CD in accordance with the platform's GitOps workflow.

## 12. Deployment Status

The Stage namespace, credentials, PVs, Helm values, rendered manifests, and IngressClass configuration were prepared and validated during the installation procedure.

Record the final deployment state only after checking the live cluster:

- Helm release status: pending live verification
- APISIX pod readiness: pending live verification
- Ingress controller readiness: pending live verification
- etcd PVC binding and health: pending live verification
- End-to-end Stage API routing: pending separate verification

This distinction ensures that a successful Helm installation is not mistaken for a fully tested API service.