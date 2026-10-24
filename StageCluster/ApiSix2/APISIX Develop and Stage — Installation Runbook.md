# APISIX Develop and Stage — Installation Runbook

## 1. Objective

Deploy two independent Apache APISIX installations in the existing Kubernetes cluster:

- **Develop:** `apisix-develop` namespace, serving `api-develop.crouseco.com`.
- **Stage:** `apisix-stage` namespace, serving `api-stage.crouseco.com`.

Both installations will be managed through Git and Argo CD.

## 2. Architecture and safety requirements

- Preserve the existing Cilium `shared-gateway` as the external cluster entry point.
- Give each APISIX installation its own Helm release, ingress-controller identity, Gateway API resources, credentials, and etcd storage.
- Preserve existing application HTTPRoutes until their Git-managed manifests are deliberately updated.
- Use the internal Nexus registry for container images and the internal Nexus Helm repository.
- Pin chart and image versions.
- Verify persistent storage before deploying etcd.

## 3. Installation procedure

### Step 1 — Verify the existing cluster

Read-only inventory commands:

```bash
kubectl get nodes -o wide
kubectl get gateway -A
kubectl get gatewayclass
kubectl get httproute -A
kubectl get pv
kubectl get pvc -A
kubectl get storageclass
```

Record the output before proceeding. Do not modify existing Cilium or application resources during this step.

### Step 2 — Verify storage and Nexus access

Inspect the worker-node storage directories and verify that the required Helm charts and container images are available through Nexus.

### Step 3 — Prepare separate configuration

Create version-pinned, Git-managed configuration for Develop and Stage, including separate etcd storage and controller identities.

### Step 4 — Deploy and verify Develop

Install through Argo CD, verify all workloads and storage, and test APISIX internally before connecting external traffic.

### Step 5 — Deploy and verify Stage

Repeat with independent resources and verify that the two installations do not interfere with each other.

### Step 6 — Connect routes

Update only the relevant Git-managed HTTPRoutes to connect the existing Cilium shared Gateway to the correct APISIX service. Update application route parent references separately through Git.

### Step 7 — End-to-end validation

Verify both API hostnames, application routing, isolation between environments, and persistence of etcd data.