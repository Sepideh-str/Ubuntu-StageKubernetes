## Worker Node Labels

Label all Kubernetes worker nodes with both a custom worker label and the standard Kubernetes worker role label.

### Apply worker labels

```bash
# BACKEND workers
kubectl label node stage-workerb1 node-role=worker
kubectl label node stage-workerb2 node-role=worker

# FRONTEND workers
kubectl label node stage-workerf1 node-role=worker
kubectl label node stage-workerf2 node-role=worker

# DMZ workers
kubectl label node stage-workerd1 node-role=worker
kubectl label node stage-workerd2 node-role=worker
```

### Apply Kubernetes-standard worker role

```bash
# BACKEND workers
kubectl label node stage-workerb1 node-role.kubernetes.io/worker=
kubectl label node stage-workerb2 node-role.kubernetes.io/worker=

# FRONTEND workers
kubectl label node stage-workerf1 node-role.kubernetes.io/worker=
kubectl label node stage-workerf2 node-role.kubernetes.io/worker=

# DMZ workers
kubectl label node stage-workerd1 node-role.kubernetes.io/worker=
kubectl label node stage-workerd2 node-role.kubernetes.io/worker=
```

### Verify

```bash
kubectl get nodes -L node-role -L node-role.kubernetes.io/worker
```

Expected result:

```text
NAME             STATUS   ROLES           NODE-ROLE   WORKER
stage-masterf1   Ready    control-plane
stage-masterf2   Ready    control-plane
stage-masterf3   Ready    control-plane
stage-workerb1   Ready    <none>          worker      <none>
stage-workerb2   Ready    <none>          worker      <none>
stage-workerd1   Ready    <none>          worker      <none>
stage-workerd2   Ready    <none>          worker      <none>
stage-workerf1   Ready    <none>          worker      <none>
stage-workerf2   Ready    <none>          worker      <none>
```

The labels can later be used with `nodeSelector`, node affinity, and other Kubernetes scheduling mechanisms to control workload placement.
