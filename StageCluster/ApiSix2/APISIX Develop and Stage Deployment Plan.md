# APISIX Develop and Stage Deployment Plan

## 1. Objective

Deploy Apache APISIX as the API management layer for the Kubernetes platform, with separate Develop and Stage environments. Use the APISIX Ingress Controller to manage routing configuration, etcd for APISIX configuration storage, and the existing Cilium shared Gateway as the external entry point.

## 2. Kubernetes worker capacity

Both frontend workers are healthy.

| Worker | CPU | Allocatable memory | Available RAM observed |
|---|---:|---:|---:|
| stage-workerf1 | 4 cores | Approximately 7.15 GiB | 5.8 GiB |
| stage-workerf2 | 4 cores | Approximately 7.15 GiB | 6.0 GiB |

Metrics Server is not currently available, so actual Kubernetes pod usage has not yet been measured. Resource requests and limits must be treated as initial settings and adjusted after deployment and load testing.

## 3. Target pod count

Each environment has seven planned pods.

| Component | Develop | Stage | Total |
|---|---:|---:|---:|
| APISIX Gateway | 2 | 2 | 4 |
| APISIX Ingress Controller | 2 | 2 | 4 |
| etcd | 3 | 3 | 6 |
| **Total** | **7** | **7** | **14** |

These counts exclude optional dashboards, temporary test pods, and other supporting workloads. Replica counts are desired counts; the actual running count must be verified after installation.

## 4. etcd storage plan

Each etcd member receives its own persistent volume and data directory.

| Environment | etcd members | Storage per member | Total |
|---|---:|---:|---:|
| Develop | 3 | 2 GiB | 6 GiB |
| Stage | 3 | 2 GiB | 6 GiB |
| **Total** | **6** | **2 GiB each** | **12 GiB** |

Storage will use the existing `/var/lib/k8s-local-storage` location on selected workers, with local PersistentVolumes and node affinity. The exact paths and node assignments will be confirmed before creating the storage manifests.

A 2 GiB volume is an initial capacity, not a guarantee that it will be sufficient indefinitely. Monitor etcd database size and available disk space.

## 5. Important availability limitation

Three etcd members can tolerate one member failure while the other two remain healthy and can communicate. However, there are only two frontend workers. If two members of the same etcd cluster run on one worker, losing that worker can remove quorum.

Therefore, this design provides etcd member-level fault tolerance, but it does not guarantee worker-level high availability. True worker-level fault tolerance requires suitable placement across at least three independent worker failure domains for each etcd cluster.

Two ingress-controller replicas also require correct leader-election and controller configuration. Two replicas alone do not guarantee independent operation.

## 6. Environment separation

- Use separate Helm releases for Develop and Stage.
- Use separate APISIX deployments and etcd clusters.
- Keep environment-specific configuration and routes separate.
- Keep the existing Cilium `shared-gateway` as the external entry point.
- Route `api-develop.crouseco.com` to the Develop APISIX service.
- Route `api-stage.crouseco.com` to the Stage APISIX service.
- Manage permanent configuration through Git and Argo CD where appropriate.

## 7. Implementation sequence

1. Verify the internal Helm repository and chart version.
2. Inspect chart values for APISIX, ingress controller, etcd, persistence, and resource settings.
3. Confirm worker placement and storage paths.
4. Prepare and review storage manifests.
5. Install Develop APISIX and verify all components.
6. Test API routing and configuration.
7. Install Stage APISIX and verify all components.
8. Connect both APISIX services through Cilium HTTPRoutes.
9. Test environment separation and document recovery procedures.

## 8. Initial resource settings for review

These are starting values to validate against the chart and actual workload, not final capacity guarantees.

| Component | CPU request | Memory request | Memory limit |
|---|---:|---:|---:|
| APISIX Gateway | 250m | 256 MiB | 512 MiB |
| Ingress Controller | 100m | 128 MiB | 256 MiB |
| etcd | 100m | 256 MiB | 512 MiB |

Resource limits and requests must be checked against the actual chart schema. APISIX traffic volume, etcd database growth, and controller workload can require higher allocations.

## 9. Completion criteria

- All intended APISIX and ingress-controller replicas are Ready.
- All etcd members are healthy and can form a quorum.
- Every etcd PVC is bound to the intended local PV.
- Develop and Stage use separate configuration stores.
- Existing Cilium Gateway resources remain intact.
- API routes reach the correct environment.
- Git/Argo CD holds the intended permanent configuration.
