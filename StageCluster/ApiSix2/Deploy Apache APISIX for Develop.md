# Deploy Apache APISIX for Develop

## 1. Purpose

Deploy an independent Apache APISIX environment for application API management in Kubernetes.

APISIX provides API gateway functionality for backend APIs. The APISIX Ingress Controller manages APISIX configuration through Kubernetes resources, including Gateway API resources.

The existing Cilium shared Gateway remains the cluster's external entry point. This deployment does not replace the Cilium Gateway or modify existing application HTTPRoutes.

## 2. Deployment architecture

| Component | Configuration |
|---|---|
| Helm release | `apisix-develop` |
| Namespace | `apisix-develop` |
| APISIX version | `3.19.0-ubuntu` |
| APISIX Ingress Controller | `2.2.0` |
| ADC | `0.27.1` |
| etcd | Bitnami legacy image, tag `latest` |
| APISIX replicas | 2 |
| Ingress Controller replicas | 2 |
| etcd members | 3 |
| Admin Service | `apisix-develop-admin:9180` |
| Admin credentials Secret | `apisix-admin-credentials` |
| Node placement | Nodes labeled `zone=frontend` |
| Image registry | `repository.crouseco.com` |

The deployment contains seven pods:

- Two APISIX gateway pods.
- Two ingress-controller pods, each running two containers.
- Three etcd pods.

The ingress-controller pods running `2/2` means both containers in each pod are ready.

## 3. Storage configuration

etcd uses persistent local storage rather than dynamically provisioned volumes.

Three PersistentVolumes were created for the Develop environment.

| PersistentVolume | Node | Capacity |
|---|---|---|
| `apisix-develop-etcd-0-pv` | `stage-workerf1` | 2Gi |
| `apisix-develop-etcd-1-pv` | `stage-workerf1` | 2Gi |
| `apisix-develop-etcd-2-pv` | `stage-workerf2` | 2Gi |

Storage configuration:

- Access mode: `ReadWriteOnce`
- Reclaim policy: `Retain`
- Storage class: empty (`storageClassName: ""`)
- PV selection labels: `app=apisix-etcd` and `environment=develop`
- Data directories: `/var/lib/k8s-local-storage/apisix-develop-etcd-0`, `apisix-develop-etcd-1`, and `apisix-develop-etcd-2` on their respective nodes.

The empty storage class prevents dynamic provisioning and allows the claims to bind to the manually created local PVs.

**Availability limitation:** two etcd members are assigned to `stage-workerf1`. Losing that worker can leave only one member available, which is insufficient for a three-member etcd quorum. This layout is not resilient to losing either worker.

## 4. Admin credentials

The Kubernetes Secret `apisix-admin-credentials` exists in the `apisix-develop` namespace.

It contains these keys:

- `admin`
- `viewer`

The APISIX Helm configuration references the Secret rather than placing credential values directly in the values file.

The ingress controller's `GatewayProxy` configuration also references the `admin` key through `secretKeyRef`.

Do not commit actual credential values to Git or print Secret data in terminal logs.

To verify the Secret without exposing its values:

```bash
kubectl get secret apisix-admin-credentials \
  -n apisix-develop \
  -o go-template='Name: {{.metadata.name}}{{"\n"}}Type: {{.type}}{{"\n"}}Keys:{{range $k, $v := .data}} {{$k}}{{end}}{{"\n"}}'
```

## 5. APISIX custom resource definitions

The APISIX-specific CRDs were installed from the local ingress-controller chart:

```bash
kubectl apply -f \
  /root/apisix/charts/apisix-ingress-controller/crds/apisixic-crds.yaml
```

The file contains 12 APISIX custom resource definitions, including:

- `GatewayProxy`
- `ApisixRoute`
- `ApisixUpstream`
- `ApisixTls`
- `ApisixConsumer`
- `ApisixGlobalRule`
- `ApisixPluginConfig`

The separate `gwapi-crds.yaml` file was not applied as part of this step, to avoid unnecessarily modifying the existing Kubernetes Gateway API CRDs used by Cilium.

Verify that the `GatewayProxy` CRD is installed:

```bash
kubectl get crd gatewayproxies.apisix.apache.org
```

List the installed APISIX resource types:

```bash
kubectl api-resources --api-group=apisix.apache.org
```

## 6. Helm values

The Develop configuration is stored at:

`/root/apisix/values-develop.yaml`

Important settings include:

```yaml
global:
  security:
    allowInsecureImages: true

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
  nodeSelector:
    zone: frontend
  persistence:
    enabled: true
    storageClass: "-"
    size: 2Gi
    selector:
      matchLabels:
        app: apisix-etcd
        environment: develop

ingress-controller:
  enabled: true
  webhook:
    enabled: false
  deployment:
    replicas: 2
  config:
    controllerName: apisix.apache.org/apisix-ingress-controller
    disableGatewayAPI: false
  gatewayProxy:
    createDefault: true
```

The actual values file also specifies the Nexus image paths, resource requests and limits, Admin Service connection, and Secret reference. Keep those settings in the complete values file rather than replacing it with this abbreviated example.

IPv6 is disabled because the environment does not support the IPv6 listener used by APISIX.

The `GatewayProxy` resource is named `apisix-develop-config`. It connects to the `apisix-develop-admin` Service on port `9180` and uses the Admin API key stored in the Kubernetes Secret.

## 7. Validate and install

Validate the chart before installing:

```bash
helm lint /root/apisix \
  -f /root/apisix/values-develop.yaml
```

Render the manifests for inspection:

```bash
helm template apisix-develop /root/apisix \
  --namespace apisix-develop \
  -f /root/apisix/values-develop.yaml \
  > /root/apisix/rendered-develop.yaml
```

Install the release:

```bash
helm install apisix-develop /root/apisix \
  --namespace apisix-develop \
  -f /root/apisix/values-develop.yaml
```

The chart passed linting, and the deployment has subsequently started successfully.

## 8. Deployment verification

### Check the pods

```bash
kubectl get pods -n apisix-develop -o wide
```

Expected workload names:

- `apisix-develop-*` — two APISIX pods
- `apisix-develop-etcd-0`
- `apisix-develop-etcd-1`
- `apisix-develop-etcd-2`
- `apisix-develop-ingress-controller-*` — two controller pods

The observed result was seven pods in `Running` state, with all containers ready and no restarts reported.

### Check the Services

```bash
kubectl get svc -n apisix-develop
```

Important Services include:

- `apisix-develop-gateway`
- `apisix-develop-admin`
- `apisix-develop-control`
- `apisix-develop-ingress-controller`
- `apisix-develop-etcd`
- `apisix-develop-etcd-headless`

The Admin Service is intended for internal control-plane communication, not direct public access.

### Check persistent volume claims

```bash
kubectl get pvc -n apisix-develop
```

All three etcd PVCs should be `Bound` to their corresponding Develop PVs.

### Check the Helm release

```bash
helm status apisix-develop -n apisix-develop
helm list -n apisix-develop
```

### Check the GatewayProxy resource

```bash
kubectl get gatewayproxy -n apisix-develop
kubectl describe gatewayproxy apisix-develop-config \
  -n apisix-develop
```

These commands verify that the custom resource exists and show its reported status, if the controller publishes one.

## 9. Current status and remaining work

**Completed:**

- APISIX-specific CRDs installed.
- Develop namespace and admin credentials Secret prepared.
- Three local etcd PVs created.
- Develop Helm configuration prepared and validated.
- APISIX, etcd, and ingress-controller pods deployed and running.

**Not yet verified by the pod listing alone:**

- etcd quorum and application-level health.
- Successful ingress-controller authentication to the APISIX Admin API.
- Successful reconciliation of the `GatewayProxy`.
- End-to-end API requests through APISIX.

**Next steps:**

1. Verify PVC binding, etcd health, and the `GatewayProxy` status.
2. Configure and test the required API routes through APISIX.
3. Configure the appropriate Cilium HTTPRoute for `api-develop.crouseco.com` without modifying unrelated application routes.
4. Repeat the deployment with separate namespace, values, credentials, PVs, and release name for Stage.

