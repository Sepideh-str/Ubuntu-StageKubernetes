# kubectl Configuration on Control-Plane Nodes


Run on each control-plane node:

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chmod 600 $HOME/.kube/config
```

Verify:

```bash
kubectl get nodes
```

The cluster nodes should be displayed.

## Why This Is Required

`kubeadm` creates the administrator kubeconfig at:

```text
/etc/kubernetes/admin.conf
```

`kubectl` uses:

```text
$HOME/.kube/config
```

by default.

Copying `admin.conf` therefore allows the administrator to use `kubectl` without specifying `--kubeconfig` every time.

## Important

This configuration is **local to the individual server**.

Therefore, if `kubectl` should be available for the root user on:

* Master-F1
* Master-F2
* Master-F3

the configuration should be performed on each server.

This does not create or change the Kubernetes cluster. It only configures the local `kubectl` client.
