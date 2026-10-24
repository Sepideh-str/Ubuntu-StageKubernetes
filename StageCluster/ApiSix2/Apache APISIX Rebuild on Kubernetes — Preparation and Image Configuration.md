# Apache APISIX Rebuild on Kubernetes — Preparation and Image Configuration

**Date:** 20 October 2026  
**Cluster:** Crouseco Kubernetes  
**Purpose:** Prepare separate Apache APISIX installations for Develop and Stage environments.

## 1. Objective

Rebuild APISIX with separate environments so that Develop and Stage have independent API gateway instances, ingress controllers, and etcd clusters.

APISIX will provide API-management capabilities. The existing Cilium Gateway API remains the cluster's external entry point.

The installation will be managed with Helm, with environment-specific configuration maintained separately.

## 2. Architecture Decisions

### 2.1 Separate environments

Two independent APISIX installations are planned:

| Component | Develop | Stage | Total |
|---|---:|---:|---:|
| APISIX gateway replicas | 2 | 2 | 4 |
| Ingress-controller replicas | 2 | 2 | 4 |
| etcd members | 3 | 3 | 6 |
| **Total planned pods** | **7** | **7** | **14** |

Each environment will have its own APISIX configuration and etcd data.

Three etcd members provide quorum-based availability, but this placement does not guarantee survival of every worker-node failure. The local PV placement must be considered when evaluating failure scenarios.

### 2.2 Network architecture

Cilium remains the external entry point. APISIX operates behind it.

Planned public API hostnames:

- `api-develop.crouseco.com`
- `api-stage.crouseco.com`

Cilium HTTPRoutes will later route these hostnames to the corresponding APISIX services. Existing application HTTPRoutes are not being changed during this preparation.

### 2.3 Existing Cilium entry point

The existing shared Gateway is retained:

- Gateway: `shared-gateway`
- GatewayClass: `cilium-nodeport`
- Namespace: `gateway-system`
- Address: `172.25.3.194`

No changes to this Gateway are required for the current preparation steps.

## 3. Cleanup Verification

The previous APISIX installation was removed before rebuilding.

The cleanup checks confirmed:

- No existing APISIX Helm release was listed.
- Previous APISIX CRDs and the APISIX GatewayClass had been removed.
- No old APISIX PersistentVolumes or PersistentVolumeClaims remained.
- Old local etcd storage directories were removed from the frontend workers.

The Kubernetes namespace `apisix` may still exist; it was not necessary to delete it as part of the cleanup.

## 4. Kubernetes Worker Nodes

The frontend workers selected for APISIX are:

| Node | IP address | Pod CIDR |
|---|---|---|
| `stage-workerf1` | `172.25.3.197` | `10.244.3.0/24` |
| `stage-workerf2` | `172.25.3.198` | `10.244.4.0/24` |

Both workers were Ready, with no reported node-pressure conditions during the preparation checks.

The local storage filesystem had approximately 40 GiB free per worker at the time of inspection.

## 5. Local Storage Preparation for etcd

Each etcd member will use a dedicated 2 GiB local PersistentVolume. The PVs use:

- Storage class: empty (`""`)
- Access mode: `ReadWriteOnce`
- Reclaim policy: `Retain`
- Filesystem volume mode
- Node affinity to the worker containing the local directory

The six PersistentVolumes were created and confirmed Available.

| PersistentVolume | Environment | Worker | Capacity |
|---|---|---|---:|
| `apisix-develop-etcd-0-pv` | Develop | `stage-workerf1` | 2 GiB |
| `apisix-develop-etcd-1-pv` | Develop | `stage-workerf1` | 2 GiB |
| `apisix-develop-etcd-2-pv` | Develop | `stage-workerf2` | 2 GiB |
| `apisix-stage-etcd-0-pv` | Stage | `stage-workerf1` | 2 GiB |
| `apisix-stage-etcd-1-pv` | Stage | `stage-workerf2` | 2 GiB |
| `apisix-stage-etcd-2-pv` | Stage | `stage-workerf2` | 2 GiB |

Total planned etcd storage is 6 GiB per environment, or 12 GiB across both environments.

The PV labels include:

- `app=apisix-etcd`
- `environment=develop` or `environment=stage`

The environment labels will be used to select the correct PVs from each Helm release's etcd configuration.

**Important:** A local PV is tied to its assigned node. The `Retain` reclaim policy also means that PV and data cleanup must be handled deliberately if an environment is removed.

## 6. Helm Chart and Image Sources

The existing Nexus Helm repository is configured as:

`https://repository.crouseco.com/repository/Apisix-helm/`

The local APISIX chart is extracted under:

`/root/apisix/`

The chart and dependency versions identified during preparation are:

| Component | Chart or application version |
|---|---|
| APISIX Helm chart | `2.18.0` |
| APISIX application | `3.19.0-ubuntu` |
| APISIX Ingress Controller | `2.2.0` |
| ADC sidecar/container | `0.27.1` |
| etcd subchart | `12.0.18` |

The local etcd dependency is under:

`/root/apisix/charts/etcd/`

The ingress-controller dependency is under:

`/root/apisix/charts/apisix-ingress-controller/`

## 7. Nexus Image Availability Checks

Because the Kubernetes environment should use Nexus rather than pull images directly from external registries, image availability was checked before installation.

The checks used the Docker Registry V2 manifest endpoint.

### 7.1 APISIX Ingress Controller

Image path checked:

`repository.crouseco.com/docker-proxy/apache/apisix-ingress-controller:2.2.0`

Result:

`HTTP 200`

This confirms that the image manifest is available through the tested Nexus path.

### 7.2 ADC image through the original GHCR path

Image path checked:

`repository.crouseco.com/v2/docker-proxy/ghcr.io/api7/adc/manifests/0.27.1`

Result:

`HTTP 404`

The image was not available at this tested path.

### 7.3 ADC image through the Docker Hub proxy

The alternative path checked was:

`repository.crouseco.com/docker-proxy/api7/adc:0.27.1`

The corresponding manifest request returned:

`HTTP 200`

This confirms that the ADC image manifest is available through the tested Nexus Docker Hub proxy path.

## 8. ADC Image Configuration Update

The local ingress-controller chart values file was updated:

`/root/apisix/charts/apisix-ingress-controller/values.yaml`

The ADC image configuration now reads:

```yaml
deployment:
  adcContainer:
    image:
      repository: repository.crouseco.com/docker-proxy/api7/adc
      tag: "0.27.1"
```

The change was verified using:

```bash
grep -n -A5 'adcContainer:' \
  /root/apisix/charts/apisix-ingress-controller/values.yaml
```

The output confirmed the Nexus repository and tag `0.27.1`.

**Configuration management note:** This edit changes the local chart's default values. Before installing the environment releases, the Nexus image override should be moved into the environment-specific values files where appropriate, rather than relying on a modification to a dependency's defaults.

## 9. Develop Namespace and Admin Credentials

The Develop namespace was created:

```bash
kubectl create namespace apisix-develop \
  --dry-run=client -o yaml | kubectl apply -f -
```

The namespace creation succeeded.

An APISIX admin credentials Secret was then created in `apisix-develop`, containing two randomly generated keys:

- `admin`
- `viewer`

The Secret name is:

`apisix-admin-credentials`

The Secret was created without printing the generated credential values. The chart's APISIX admin configuration supports referring to this Secret.

The ingress controller's Admin API authentication must also reference the appropriate admin key from the Secret, instead of relying on the chart's example/default key.

The corresponding Secret has not yet been confirmed for the Stage namespace.

## 10. Current Preparation Status

| Item | Status |
|---|---|
| Previous APISIX installation cleanup | Completed |
| Cilium shared Gateway retained | Confirmed |
| Six etcd local PVs created | Completed |
| Develop namespace created | Completed |
| Develop admin credentials Secret created | Completed |
| Ingress-controller image manifest available through Nexus | Confirmed |
| ADC image manifest available through Nexus Docker proxy | Confirmed |
| ADC repository updated in local chart values | Completed |
| Environment-specific Develop values file | Not yet finalized |
| Stage namespace and admin credentials | To be prepared/verified |
| Helm manifest rendering and review | Not yet completed |
| Develop installation | Not yet started |
| Stage installation | Not yet started |
| Public API routing through Cilium | Later step |

## 11. Next Steps

The next task is to prepare `/root/apisix/values-develop.yaml` with the settings needed for the Develop installation, including:

1. APISIX image and two gateway replicas.
2. Two ingress-controller replicas and the Nexus ADC image.
3. The correct APISIX Admin API service name and namespace.
4. Admin API authentication using the `apisix-admin-credentials` Secret.
5. IPv6 disabled, based on the previous installation's observed IPv6 socket failure.
6. Three etcd members with 2 GiB persistence and PV selectors for `environment=develop`.
7. Frontend worker placement and conservative resource requests/limits.
8. The existing Cilium Gateway left unchanged.

After preparing the values file, render the Helm manifests locally and inspect the resulting image paths, service names, Secret references, node selectors, and PVC selectors before installing anything.

The same approach will then be applied to Stage using its own namespace, credentials, values file, and etcd PV selectors.
