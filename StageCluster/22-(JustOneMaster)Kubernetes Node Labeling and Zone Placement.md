# Kubernetes Node Labeling and Zone Placement

## Purpose

Kubernetes worker nodes are labeled according to their network/application zone so workloads can be scheduled onto the appropriate nodes.

The cluster is divided into three worker zones:

* **Backend** — backend services
* **Frontend** — internal/frontend services and platform components such as Argo CD
* **DMZ** — internet-facing workloads

Control-plane nodes are not assigned a zone because they are reserved for Kubernetes control-plane components and are normally protected by the control-plane `NoSchedule` taint.

## Node Labels

### Backend

| Node             | Zone      |
| ---------------- | --------- |
| `stage-workerb1` | `backend` |
| `stage-workerb2` | `backend` |

Label:

```bash
kubectl label node stage-workerb1 zone=backend
kubectl label node stage-workerb2 zone=backend
```

### Frontend

| Node             | Zone       |
| ---------------- | ---------- |
| `stage-workerf1` | `frontend` |
| `stage-workerf2` | `frontend` |

Label:

```bash
kubectl label node stage-workerf1 zone=frontend
kubectl label node stage-workerf2 zone=frontend
```

### DMZ

| Node             | Zone  |
| ---------------- | ----- |
| `stage-workerd1` | `dmz` |
| `stage-workerd2` | `dmz` |

Label:

```bash
kubectl label node stage-workerd1 zone=dmz
kubectl label node stage-workerd2 zone=dmz
```

## Control-Plane Nodes

The following nodes are control-plane nodes and do not require a `zone` label:

```text
stage-masterf1
stage-masterf2
stage-masterf3
```

They already have the Kubernetes control-plane label:

```text
node-role.kubernetes.io/control-plane=
```

and are normally protected from regular workload scheduling by the control-plane taint.

## Verify Labels

To display the zone alongside the nodes:

```bash
kubectl get nodes -L zone
```

To display all labels:

```bash
kubectl get nodes --show-labels
```

To inspect one node:

```bash
kubectl get node <node-name> --show-labels
```

## Scheduling Workloads by Zone

A workload can be restricted to a specific zone using `nodeSelector`.

For example, to schedule a workload only on Frontend nodes:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        zone: frontend
```

Similarly:

```yaml
nodeSelector:
  zone: backend
```

restricts the workload to Backend nodes.

And:

```yaml
nodeSelector:
  zone: dmz
```

restricts the workload to DMZ nodes.

## Current Zone Layout

```text
Kubernetes Cluster
│
├── Control Plane
│   ├── stage-masterf1
│   ├── stage-masterf2
│   └── stage-masterf3
│
├── Backend
│   ├── stage-workerb1
│   └── stage-workerb2
│
├── Frontend
│   ├── stage-workerf1
│   └── stage-workerf2
│
└── DMZ
    ├── stage-workerd1
    └── stage-workerd2
```

## Important Note

The `zone` label is a **custom label used by this Kubernetes environment**. Labels such as `kubernetes.io/os`, `kubernetes.io/arch`, and `kubernetes.io/hostname` are standard Kubernetes/node labels.

The zone label provides a simple mechanism for workload placement. Network isolation between Backend, Frontend, and DMZ remains a separate concern and is enforced through the network/firewall configuration and Kubernetes networking policies where applicable.
